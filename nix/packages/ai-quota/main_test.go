package main

import (
	"math"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHumanDeltaUsesElapsedUnits(t *testing.T) {
	tests := []struct {
		seconds int64
		want    string
	}{
		{0, "now"},
		{59, "0m"},
		{60, "1m"},
		{3599, "59m"},
		{3600, "1h 0m"},
		{13207, "3h 40m"},
		{86399, "23h 59m"},
		{86400, "1d 0h"},
		{176400, "2d 1h"},
	}

	for _, tt := range tests {
		if got := humanDelta(tt.seconds); got != tt.want {
			t.Errorf("humanDelta(%d) = %q, want %q", tt.seconds, got, tt.want)
		}
	}
}

func TestFetchUsageInsights(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got := r.Header.Get("Authorization"); got != "Bearer secret" {
			t.Errorf("Authorization = %q, want Bearer secret", got)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{
			"generated_at":"2026-08-28T05:04:01Z",
			"models":[{
				"provider":"codex","model":"gpt-5.6-sol","api_calls":26,
				"failed_api_calls":1,"input_tokens":167302,"cache_read_tokens":1780736,
				"cache_write_tokens":0,"output_tokens":18422,"total_tokens":1966460,
				"cache_hit_rate":0.9141176917493395,"cost_usd":2.066112,
				"priced_api_calls":26,"unpriced_api_calls":0
			}],
			"period":{"from":"1970-01-01T00:00:00Z","to":"2026-08-28T05:04:01Z","end_exclusive":true},
			"totals":{"api_calls":26,"failed_api_calls":1,"input_tokens":167302,
				"cache_read_tokens":1780736,"cache_write_tokens":0,"output_tokens":18422,
				"total_tokens":1966460,"cache_hit_rate":0.9141176917493395,
				"cost_usd":2.066112,"priced_api_calls":26,"unpriced_api_calls":0}
		}`))
	}))
	defer server.Close()

	insights, err := fetchUsageInsights(server.Client(), "secret", server.URL)
	if err != nil {
		t.Fatalf("fetchUsageInsights() error = %v", err)
	}
	if len(insights.Models) != 1 {
		t.Fatalf("len(models) = %d, want 1", len(insights.Models))
	}
	model := insights.Models[0]
	if model.Provider != "codex" || model.Model != "gpt-5.6-sol" {
		t.Errorf("model key = %s/%s, want codex/gpt-5.6-sol", model.Provider, model.Model)
	}
	if model.TotalTokens != 1966460 || model.PricedAPICalls != 26 {
		t.Errorf("model aggregate = %+v", model.UsageAggregate)
	}
	if !insights.Period.EndExclusive {
		t.Error("period.end_exclusive = false, want true")
	}
}

func TestFetchUsageInsightsReportsHTTPError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, `{"error":"plugin unavailable"}`, http.StatusServiceUnavailable)
	}))
	defer server.Close()

	_, err := fetchUsageInsights(server.Client(), "secret", server.URL)
	if err == nil {
		t.Fatal("fetchUsageInsights() error = nil, want HTTP error")
	}
	want := `HTTP 503: {"error":"plugin unavailable"}`
	if err.Error() != want {
		t.Errorf("error = %q, want %q", err, want)
	}
}

func TestAggregateUsageRecomputesCacheHitRate(t *testing.T) {
	models := []ModelUsage{
		{UsageAggregate: UsageAggregate{APICalls: 2, InputTokens: 100, CacheReadTokens: 900, CostUSD: 1, PricedAPICalls: 2}},
		{UsageAggregate: UsageAggregate{APICalls: 1, InputTokens: 900, CacheReadTokens: 100, CostUSD: 2, UnpricedAPICalls: 1}},
	}

	got := aggregateUsage(models)
	if got.APICalls != 3 || got.InputTokens != 1000 || got.CacheReadTokens != 1000 || got.CostUSD != 3 {
		t.Errorf("aggregateUsage() = %+v", got)
	}
	if math.Abs(got.CacheHitRate-0.5) > 1e-12 {
		t.Errorf("cache hit rate = %f, want 0.5", got.CacheHitRate)
	}
	if got.PricedAPICalls != 2 || got.UnpricedAPICalls != 1 {
		t.Errorf("price coverage = %d/%d, want 2/1", got.PricedAPICalls, got.UnpricedAPICalls)
	}
}

func TestAccountDisplayNamePrefersUserIdentity(t *testing.T) {
	subtitle := "person@example.com (plus)"
	tests := []struct {
		account Account
		want    string
	}{
		{Account{Name: "codex-generated-name.json", Subtitle: &subtitle}, subtitle},
		{Account{Name: "antigravity-person@example.com.json"}, "person@example.com"},
		{Account{Name: "OpenCode Go"}, "OpenCode Go"},
	}
	for _, tt := range tests {
		if got := accountDisplayName(tt.account); got != tt.want {
			t.Errorf("accountDisplayName(%q) = %q, want %q", tt.account.Name, got, tt.want)
		}
	}
}

func TestQuotaLineIsCompact(t *testing.T) {
	resetHuman := "4h 30m"
	resetLocal := "Aug 28 11:15"
	line := quotaLine(Meter{Pct: 30, ResetHuman: &resetHuman, ResetLocal: &resetLocal})
	for _, want := range []string{"━━━━", "30%", "resets in 4h 30m", "Aug 28 11:15"} {
		if !strings.Contains(line, want) {
			t.Errorf("quotaLine() = %q, want substring %q", line, want)
		}
	}
	if strings.Contains(line, "used") {
		t.Errorf("quotaLine() = %q, should not repeat the meaning of the percentage", line)
	}
}

func TestUsageFormatting(t *testing.T) {
	counts := map[int64]string{
		999:     "999",
		1000:    "1K",
		1234:    "1.23K",
		1000000: "1M",
	}
	for value, want := range counts {
		if got := compactCount(value); got != want {
			t.Errorf("compactCount(%d) = %q, want %q", value, got, want)
		}
	}

	costs := map[float64]string{
		0:        "$0.00",
		2:        "$2.00",
		2.066112: "$2.07",
		0.017957: "$0.018",
	}
	for value, want := range costs {
		if got := formatCostUSD(value); got != want {
			t.Errorf("formatCostUSD(%f) = %q, want %q", value, got, want)
		}
	}
}
