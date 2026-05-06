package clientsauth

import (
	"database/sql"
	"fmt"

	"github.com/go-sql-driver/mysql"
	"github.com/jmoiron/sqlx"
	"github.com/mattn/go-sqlite3"

	"github.com/openrport/openrport/share/query"

	"github.com/openrport/openrport/share/enums"
)

const mysqlDuplicateEntryErrorCode = 1062

type DatabaseProvider struct {
	db        *sqlx.DB
	tableName string
	tagsTable string
	converter *query.SQLConverter
}

var _ Provider = &DatabaseProvider{}

func NewDatabaseProvider(DB *sqlx.DB, tableName string) *DatabaseProvider {
	p := &DatabaseProvider{
		db:        DB,
		tableName: tableName,
		tagsTable: tableName + "_tags",
		converter: query.NewSQLConverter(DB.DriverName()),
	}
	// Best-effort auto-create of the side table that holds optional per-credential
	// tags. Errors are ignored so a read-only DB user does not fail at startup;
	// tag-aware writes will surface the underlying error to the caller.
	_, _ = p.db.Exec(fmt.Sprintf(
		"CREATE TABLE IF NOT EXISTS %s (client_auth_id VARCHAR(255) NOT NULL, tag VARCHAR(255) NOT NULL, PRIMARY KEY (client_auth_id, tag))",
		p.tagsTable,
	))
	return p
}

func (c *DatabaseProvider) GetFiltered(filter *query.ListOptions) ([]*ClientAuth, int, error) {

	filter.Sorts = append(filter.Sorts, query.SortOption{Column: "id", IsASC: true})
	rQuery, rParams := c.converter.ConvertListOptionsToQuery(filter, fmt.Sprintf("SELECT id,password FROM %s", c.tableName))
	filter.Pagination = nil
	filter.Sorts = nil
	cQuery, cParams := c.converter.ConvertListOptionsToQuery(filter, fmt.Sprintf("SELECT COUNT(id) FROM %s", c.tableName))
	var count = 0
	if err := c.db.Get(&count, cQuery, cParams...); err != nil {
		return nil, 0, err
	}
	var result = []*ClientAuth{}
	if err := c.db.Select(&result, rQuery, rParams...); err != nil {
		return nil, 0, err
	}
	if err := c.attachTags(result); err != nil {
		return nil, 0, err
	}
	return result, count, nil
}

func (c *DatabaseProvider) Get(id string) (*ClientAuth, error) {
	result := &ClientAuth{}
	err := c.db.Get(result, fmt.Sprintf("SELECT id, password FROM %s WHERE id = ?", c.tableName), id)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	tags, err := c.loadTags(id)
	if err != nil {
		return nil, err
	}
	result.Tags = tags
	return result, nil
}

func (c *DatabaseProvider) Add(client *ClientAuth) (bool, error) {
	_, err := c.db.NamedExec(fmt.Sprintf("INSERT INTO %s (id, password) VALUES (:id, :password)", c.tableName), client)
	if err != nil {
		// Check for client already exists error
		switch typeErr := err.(type) {
		case sqlite3.Error:
			if typeErr.Code == sqlite3.ErrConstraint {
				return false, nil
			}
		case *mysql.MySQLError:
			if typeErr.Number == mysqlDuplicateEntryErrorCode {
				return false, nil
			}
		}
		return false, err
	}
	if err := c.replaceTags(client.ID, client.Tags); err != nil {
		return true, err
	}
	return true, nil
}

func (c *DatabaseProvider) Delete(id string) error {
	if _, err := c.db.Exec(fmt.Sprintf("DELETE FROM %s WHERE client_auth_id = ?", c.tagsTable), id); err != nil {
		return err
	}
	_, err := c.db.Exec(fmt.Sprintf("DELETE FROM %s WHERE id = ?", c.tableName), id)
	return err
}

// loadTags returns the list of tags associated with the given client auth id,
// sorted ascending. An empty (nil) slice is returned when no tags are present.
func (c *DatabaseProvider) loadTags(id string) ([]string, error) {
	var tags []string
	err := c.db.Select(&tags, fmt.Sprintf("SELECT tag FROM %s WHERE client_auth_id = ? ORDER BY tag ASC", c.tagsTable), id)
	if err != nil {
		return nil, err
	}
	return tags, nil
}

// attachTags fills in the Tags field on each ClientAuth in the slice using a
// single round-trip per id. Kept simple over a JOIN to keep the SQL portable
// across the SQL driver matrix sqlx already has to deal with elsewhere.
func (c *DatabaseProvider) attachTags(rows []*ClientAuth) error {
	for _, r := range rows {
		tags, err := c.loadTags(r.ID)
		if err != nil {
			return err
		}
		r.Tags = tags
	}
	return nil
}

// replaceTags removes any existing tags for the given id and inserts the
// provided set. A nil/empty slice is treated as "no tags" and just clears the
// rows.
func (c *DatabaseProvider) replaceTags(id string, tags []string) error {
	if _, err := c.db.Exec(fmt.Sprintf("DELETE FROM %s WHERE client_auth_id = ?", c.tagsTable), id); err != nil {
		return err
	}
	for _, t := range tags {
		if t == "" {
			continue
		}
		if _, err := c.db.Exec(fmt.Sprintf("INSERT INTO %s (client_auth_id, tag) VALUES (?, ?)", c.tagsTable), id, t); err != nil {
			return err
		}
	}
	return nil
}

func (c *DatabaseProvider) IsWriteable() bool {
	return true
}

func (c *DatabaseProvider) Source() enums.ProviderSource {
	return enums.ProviderSourceDB
}
