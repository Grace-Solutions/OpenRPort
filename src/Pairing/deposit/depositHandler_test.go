package deposit_test

import (
	"bytes"
	"encoding/json"
	"github.com/openrport/rport-pairing/deposit"
	"github.com/openrport/rport-pairing/internal/cache"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

var FormFields = map[string]string{
	"password":    "foobaz",
	"connect_url": "https://rport.example.com",
	"fingerprint": "2a:c1:71:09:80:ba:7c:10:05:e5:2c:99:6d:15:56:24",
	"client_id":   "client1",
}

func TestFormRequest(t *testing.T) {
	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	for k, v := range FormFields {
		var fw io.Writer
		var err error
		fw, err = writer.CreateFormField(k)
		require.NoError(t, err)
		_, err = io.Copy(fw, strings.NewReader(v))
		require.NoError(t, err)
	}
	// Two repeated tag fields plus a comma-separated value to exercise the
	// multi-value + CSV split paths of splitTagValues.
	for _, tag := range []string{"prod", "us-east", "build:42, owner:ops"} {
		fw, err := writer.CreateFormField("tags")
		require.NoError(t, err)
		_, err = io.Copy(fw, strings.NewReader(tag))
		require.NoError(t, err)
	}
	err := writer.Close()
	require.NoError(t, err)
	t.Log("From request")
	request, _ := http.NewRequest(http.MethodPost, "/", bytes.NewReader(body.Bytes()))
	request.Header.Set("Content-Type", writer.FormDataContentType())
	executeAndValidate(t, request, []string{"prod", "us-east", "build:42", "owner:ops"})
}

func TestJsonRequest(t *testing.T) {
	payload := map[string]interface{}{}
	for k, v := range FormFields {
		payload[k] = v
	}
	payload["tags"] = []string{"prod", "us-east"}
	body, err := json.Marshal(payload)
	require.NoError(t, err)
	t.Logf("Json request with payload created %s", body)
	request, _ := http.NewRequest(http.MethodPost, "/", bytes.NewReader(body))
	request.Header.Set("Content-Type", "application/json")
	executeAndValidate(t, request, []string{"prod", "us-east"})
}

func executeAndValidate(t *testing.T, request *http.Request, expectedTags []string) {
	recorder := httptest.NewRecorder()
	c := cache.New()
	// Create request handlers
	depositHandler := &deposit.Handler{Cache: c}
	depositHandler.ServeHTTP(recorder, request)
	t.Log("Got response code", recorder.Result().StatusCode)
	t.Log("Got response body", recorder.Body.String())
	assert.Equal(t, 200, recorder.Result().StatusCode)
	var response deposit.Response
	err := json.Unmarshal(recorder.Body.Bytes(), &response)
	require.NoError(t, err)
	t.Log("Got pairing code ", response.PairingCode)
	// Assert the returned pairing code equals the one stored in the cache
	cached, ok := c.Get(response.PairingCode)
	assert.True(t, ok, "Pairing code not found in cache")
	dep := cached.(deposit.Deposit)
	assert.Equal(t, expectedTags, dep.Tags, "Tags did not round-trip through the cache")
}
