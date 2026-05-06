package clientsauth

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/ioutil"
	"os"
	"sort"
	"time"

	"github.com/patrickmn/go-cache"

	"github.com/openrport/openrport/share/enums"
	"github.com/openrport/openrport/share/query"
)

// FileProvider is file based client provider.
// It is not thread save so should be surrounded by CachedProvider.
type FileProvider struct {
	fileName string
	cache    *cache.Cache
}

// fileEntry is the on-disk representation of a single client auth record.
// To preserve compatibility with the legacy {"id": "password"} layout, the
// custom UnmarshalJSON accepts either a bare string (treated as password
// with no tags) or an object {"password": "...", "tags": [...]}.
type fileEntry struct {
	Password string   `json:"password"`
	Tags     []string `json:"tags,omitempty"`
}

func (e *fileEntry) UnmarshalJSON(data []byte) error {
	var s string
	if err := json.Unmarshal(data, &s); err == nil {
		e.Password = s
		return nil
	}
	var alias struct {
		Password string   `json:"password"`
		Tags     []string `json:"tags,omitempty"`
	}
	if err := json.Unmarshal(data, &alias); err != nil {
		return err
	}
	e.Password = alias.Password
	e.Tags = alias.Tags
	return nil
}

var _ Provider = &FileProvider{}

func NewFileProvider(fileName string, cache *cache.Cache) *FileProvider {
	return &FileProvider{
		fileName: fileName,
		cache:    cache,
	}
}

// GetAll returns rport clients auth credentials from a given file.
func (c *FileProvider) getAll() ([]*ClientAuth, error) {
	entries, err := c.load()
	if err != nil {
		return nil, fmt.Errorf("failed to decode rport clients auth file: %v", err)
	}

	var res []*ClientAuth
	for id, entry := range entries {
		if id == "" || entry.Password == "" {
			return nil, errors.New("empty client auth ID or password is not allowed")
		}
		res = append(res, &ClientAuth{ID: id, Password: entry.Password, Tags: entry.Tags})
	}

	return res, nil
}

func (c *FileProvider) GetFiltered(filter *query.ListOptions) ([]*ClientAuth, int, error) {
	var ca []*ClientAuth
	ca, err := c.getAll()
	if err != nil {
		return nil, 0, err
	}
	if len(filter.Filters) > 0 {
		var filtered = []*ClientAuth{}
		for _, v := range ca {
			match, err := query.MatchesFilters(v, filter.Filters)
			if err != nil {
				return nil, 0, err
			}
			if match {
				filtered = append(filtered, &ClientAuth{ID: v.ID, Password: v.Password, Tags: v.Tags})
			}
		}
		ca = filtered
	}
	c.SortByID(ca, false)
	l := len(ca)
	start, end := filter.Pagination.GetStartEnd(l)
	return ca[start:end], l, nil
}

func (c *FileProvider) Get(id string) (*ClientAuth, error) {
	if val, _ := c.cache.Get(c.CacheKey(id)); val != nil {
		return val.(*ClientAuth), nil
	}
	entries, err := c.load()
	if err != nil {
		return nil, fmt.Errorf("failed to decode rport clients auth file: %v", err)
	}
	if e, ok := entries[id]; ok {
		ca := &ClientAuth{ID: id, Password: e.Password, Tags: e.Tags}
		if err := c.cache.Add(c.CacheKey(id), ca, 60*time.Minute); err != nil {
			return nil, err
		}
		return ca, nil
	}
	return nil, nil
}

func (c *FileProvider) Add(clientAuth *ClientAuth) (bool, error) {
	entries, err := c.load()
	if err != nil {
		return false, fmt.Errorf("failed to decode rport clients auth file: %v", err)
	}

	clientID := clientAuth.ID

	if _, ok := entries[clientID]; ok {
		return false, nil
	}

	entries[clientID] = fileEntry{Password: clientAuth.Password, Tags: clientAuth.Tags}

	if err := c.save(entries); err != nil {
		return false, fmt.Errorf("failed to encode rport clients auth file: %v", err)
	}

	return true, nil
}

func (c *FileProvider) Delete(id string) error {
	entries, err := c.load()
	if err != nil {
		return fmt.Errorf("failed to decode rport clients auth file: %v", err)
	}

	delete(entries, id)
	c.cache.Delete(c.CacheKey(id))

	if err := c.save(entries); err != nil {
		return fmt.Errorf("failed to encode rport clients auth file: %v", err)
	}

	return nil
}

func (c *FileProvider) IsWriteable() bool {
	return true
}

func (c *FileProvider) load() (map[string]fileEntry, error) {
	b, err := ioutil.ReadFile(c.fileName)
	if err != nil {
		return nil, fmt.Errorf("failed to read rport clients auth file %q: %s", c.fileName, err)
	}

	entries := map[string]fileEntry{}
	if err := json.Unmarshal(b, &entries); err != nil {
		return nil, err
	}

	return entries, nil
}

func (c *FileProvider) save(entries map[string]fileEntry) error {
	file, err := os.OpenFile(c.fileName, os.O_RDWR|os.O_TRUNC, os.ModePerm)
	if err != nil {
		return fmt.Errorf("failed to open rport clients auth file: %v", err)
	}
	defer file.Close()

	encoder := json.NewEncoder(file)
	encoder.SetIndent("", "	")
	if err := encoder.Encode(entries); err != nil {
		return fmt.Errorf("failed to write rport clients auth: %v", err)
	}

	return nil
}

func (c *FileProvider) Source() enums.ProviderSource {
	return enums.ProviderSourceFile
}

func (c *FileProvider) SortByID(a []*ClientAuth, desc bool) {
	sort.Slice(a, func(i, j int) bool {
		less := a[i].ID < a[j].ID
		if desc {
			return !less
		}
		return less
	})
}

func (c *FileProvider) CacheKey(id string) string {
	return "client-auth-" + id
}
