// Fetch quota for direct subscriptions and accounts on the tailnet AI proxy,
// plus per-provider/model usage and cost aggregates from CLIProxyAPI.
//
// Proxy providers use CLIProxyAPI's management /api-call endpoint. Direct
// providers authenticate from their own agenix-provisioned key files.
//
// Pass --json for machine-readable output (consumed by the bar pills).
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	apiBase          = "https://ai-proxy.at-basking.ts.net"
	mgmt             = apiBase + "/v0/management"
	usageInsightsURL = mgmt + "/plugins/usage-insights/models"
	defaultKeyFile   = "~/.secrets/ai-proxy-mgmt-key"
	defaultOCKeyFile = "~/.secrets/opencode-api-key"
	opencodeUsageURL = "https://opencode.ai/zen/go/v1/usage"

	barWidth = 12
)

const (
	reset   = "\033[0m"
	bold    = "\033[1m"
	dim     = "\033[2m"
	red     = "\033[31m"
	green   = "\033[32m"
	yellow  = "\033[33m"
	cyan    = "\033[36m"
	magenta = "\033[35m"
)

func paint(text string, codes ...string) string {
	return strings.Join(codes, "") + text + reset
}

func expandHome(path string) string {
	if strings.HasPrefix(path, "~/") {
		if home, err := os.UserHomeDir(); err == nil {
			return home + path[1:]
		}
	}
	return path
}

func loadKey(envName, fileEnvName, defaultFile string) string {
	if key := os.Getenv(envName); key != "" {
		return key
	}
	keyFile := os.Getenv(fileEnvName)
	if keyFile == "" {
		keyFile = defaultFile
	}
	data, err := os.ReadFile(expandHome(keyFile))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
}

// --- value coercion helpers (Python int()/float() equivalents) ---

func toInt(v any) (int64, bool) {
	switch n := v.(type) {
	case float64:
		return int64(n), true
	case string:
		i, err := strconv.ParseInt(strings.TrimSpace(n), 10, 64)
		if err == nil {
			return i, true
		}
		f, err := strconv.ParseFloat(strings.TrimSpace(n), 64)
		if err == nil {
			return int64(f), true
		}
	}
	return 0, false
}

func toFloat(v any) (float64, bool) {
	switch n := v.(type) {
	case float64:
		return n, true
	case string:
		f, err := strconv.ParseFloat(strings.TrimSpace(n), 64)
		if err == nil {
			return f, true
		}
	}
	return 0, false
}

func pyStr(v any, fallback string) string {
	switch s := v.(type) {
	case nil:
		return fallback
	case string:
		return s
	case float64:
		if s == math.Trunc(s) {
			return strconv.FormatInt(int64(s), 10)
		}
		return strconv.FormatFloat(s, 'g', -1, 64)
	case bool:
		if s {
			return "True"
		}
		return "False"
	}
	return fmt.Sprint(v)
}

func parseTime(v any) *time.Time {
	s, ok := v.(string)
	if !ok || s == "" {
		return nil
	}
	if t, err := time.Parse(time.RFC3339Nano, s); err == nil {
		return &t
	}
	return nil
}

func parseEpoch(v any) *time.Time {
	ts, ok := toInt(v)
	if !ok {
		return nil
	}
	t := time.Unix(ts, 0).UTC()
	return &t
}

func humanDelta(seconds int64) string {
	if seconds <= 0 {
		return "now"
	}
	minutes := seconds / 60
	days := minutes / (60 * 24)
	minutes %= 60 * 24
	hours := minutes / 60
	minutes %= 60
	if days > 0 {
		return fmt.Sprintf("%dd %dh", days, hours)
	}
	if hours > 0 {
		return fmt.Sprintf("%dh %dm", hours, minutes)
	}
	return fmt.Sprintf("%dm", minutes)
}

func usageColor(pct float64) string {
	if pct >= 90 {
		return red
	}
	if pct >= 70 {
		return yellow
	}
	return green
}

func windowLabel(seconds any) string {
	s, ok := toInt(seconds)
	if !ok || s == 0 {
		return "window"
	}
	for _, u := range []struct {
		unit string
		size int64
	}{
		{"week", 604800},
		{"day", 86400},
		{"hour", 3600},
		{"min", 60},
	} {
		if s >= u.size && s%u.size == 0 {
			n := s / u.size
			if u.unit == "week" && n == 1 {
				return "weekly"
			}
			if u.unit == "day" && n == 1 {
				return "daily"
			}
			return fmt.Sprintf("%d-%s", n, u.unit)
		}
	}
	return fmt.Sprintf("%ds", s)
}

// --- output model (must match the schema consumed by summary.jq) ---

type Meter struct {
	Label      string  `json:"label"`
	Pct        float64 `json:"pct"`
	Reset      *string `json:"reset"`
	ResetIn    *int64  `json:"reset_in"`
	ResetHuman *string `json:"reset_human"`
	ResetLocal *string `json:"reset_local"`
}

type Account struct {
	Name     string      `json:"name"`
	Subtitle *string     `json:"subtitle"`
	Error    *string     `json:"error"`
	Meters   []Meter     `json:"meters"`
	Notes    [][2]string `json:"notes"`
}

type Provider struct {
	Provider string    `json:"provider"`
	Accounts []Account `json:"accounts"`
}

type UsageAggregate struct {
	APICalls         int64   `json:"api_calls"`
	FailedAPICalls   int64   `json:"failed_api_calls"`
	InputTokens      int64   `json:"input_tokens"`
	CacheReadTokens  int64   `json:"cache_read_tokens"`
	CacheWriteTokens int64   `json:"cache_write_tokens"`
	OutputTokens     int64   `json:"output_tokens"`
	TotalTokens      int64   `json:"total_tokens"`
	CacheHitRate     float64 `json:"cache_hit_rate"`
	CostUSD          float64 `json:"cost_usd"`
	PricedAPICalls   int64   `json:"priced_api_calls"`
	UnpricedAPICalls int64   `json:"unpriced_api_calls"`
}

type ModelUsage struct {
	Provider string `json:"provider"`
	Model    string `json:"model"`
	UsageAggregate
}

type UsagePeriod struct {
	From         string `json:"from"`
	To           string `json:"to"`
	EndExclusive bool   `json:"end_exclusive"`
}

type UsageInsights struct {
	GeneratedAt string         `json:"generated_at"`
	Models      []ModelUsage   `json:"models"`
	Period      UsagePeriod    `json:"period"`
	Totals      UsageAggregate `json:"totals"`
}

type rawMeter struct {
	label string
	pct   float64
	reset *time.Time
}

func finalizeMeters(raw []rawMeter, now time.Time) []Meter {
	meters := make([]Meter, 0, len(raw))
	for _, m := range raw {
		out := Meter{Label: m.label, Pct: m.pct}
		if m.reset != nil {
			iso := m.reset.UTC().Format(time.RFC3339Nano)
			secs := int64(m.reset.Sub(now).Seconds())
			human := humanDelta(secs)
			local := m.reset.Local().Format("Jan 02 15:04")
			out.Reset = &iso
			out.ResetIn = &secs
			out.ResetHuman = &human
			out.ResetLocal = &local
		}
		meters = append(meters, out)
	}
	return meters
}

// detailMeter mirrors the Python meter(): pct from used/limit.
func detailMeter(label string, detail map[string]any) rawMeter {
	used, uok := toInt(detail["used"])
	limit, lok := toInt(detail["limit"])
	pct := 0.0
	if uok && lok && limit != 0 {
		pct = float64(used) / float64(limit) * 100
	}
	return rawMeter{label: label, pct: pct, reset: parseTime(detail["resetTime"])}
}

// --- provider response parsers ---

type parseFunc func(body []byte) (*string, []rawMeter, [][2]string, error)

func parseKimi(body []byte) (*string, []rawMeter, [][2]string, error) {
	var resp struct {
		User struct {
			UserID     string `json:"userId"`
			Region     string `json:"region"`
			Membership struct {
				Level string `json:"level"`
			} `json:"membership"`
		} `json:"user"`
		Usage  map[string]any `json:"usage"`
		Limits []struct {
			Window struct {
				Duration any    `json:"duration"`
				TimeUnit string `json:"timeUnit"`
			} `json:"window"`
			Detail map[string]any `json:"detail"`
		} `json:"limits"`
		Parallel map[string]any `json:"parallel"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, nil, nil, err
	}

	region := strings.ToLower(strings.ReplaceAll(pyStr(any(resp.User.Region), "?"), "REGION_", ""))
	level := strings.ToLower(strings.ReplaceAll(pyStr(any(resp.User.Membership.Level), "?"), "LEVEL_", ""))
	userID := resp.User.UserID
	if userID == "" {
		userID = "?"
	}
	subtitle := fmt.Sprintf("%s (%s, %s)", userID, region, level)

	meters := []rawMeter{detailMeter("weekly", resp.Usage)}
	for _, w := range resp.Limits {
		unit := strings.ToLower(strings.ReplaceAll(w.Window.TimeUnit, "TIME_UNIT_", ""))
		label := fmt.Sprintf("%s-%s", pyStr(w.Window.Duration, "?"), unit)
		meters = append(meters, detailMeter(label, w.Detail))
	}

	var notes [][2]string
	if limit, ok := toInt(resp.Parallel["limit"]); ok && len(resp.Parallel) > 0 {
		notes = append(notes, [2]string{"parallel", fmt.Sprintf("%d concurrent", limit)})
	}
	return &subtitle, meters, notes, nil
}

func parseCodex(body []byte) (*string, []rawMeter, [][2]string, error) {
	type window struct {
		UsedPercent        any `json:"used_percent"`
		LimitWindowSeconds any `json:"limit_window_seconds"`
		ResetAt            any `json:"reset_at"`
	}
	type rateLimit struct {
		PrimaryWindow   *window `json:"primary_window"`
		SecondaryWindow *window `json:"secondary_window"`
	}
	var resp struct {
		Email               string         `json:"email"`
		PlanType            string         `json:"plan_type"`
		RateLimit           *rateLimit     `json:"rate_limit"`
		CodeReviewRateLimit *rateLimit     `json:"code_review_rate_limit"`
		Credits             map[string]any `json:"credits"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, nil, nil, err
	}

	email, plan := resp.Email, resp.PlanType
	if email == "" {
		email = "?"
	}
	if plan == "" {
		plan = "?"
	}
	subtitle := fmt.Sprintf("%s (%s)", email, plan)

	var meters []rawMeter
	for _, entry := range []struct {
		rl     *rateLimit
		prefix string
	}{
		{resp.RateLimit, ""},
		{resp.CodeReviewRateLimit, "review "},
	} {
		if entry.rl == nil {
			continue
		}
		for _, win := range []*window{entry.rl.PrimaryWindow, entry.rl.SecondaryWindow} {
			if win == nil {
				continue
			}
			pct, _ := toFloat(win.UsedPercent)
			meters = append(meters, rawMeter{
				label: entry.prefix + windowLabel(win.LimitWindowSeconds),
				pct:   pct,
				reset: parseEpoch(win.ResetAt),
			})
		}
	}

	var notes [][2]string
	if has, _ := resp.Credits["has_credits"].(bool); has {
		notes = append(notes, [2]string{"credits", "balance " + pyStr(resp.Credits["balance"], "?")})
	}
	return &subtitle, meters, notes, nil
}

func commonPrefix(strs []string) string {
	if len(strs) == 0 {
		return ""
	}
	prefix := strs[0]
	for _, s := range strs[1:] {
		for !strings.HasPrefix(s, prefix) {
			if prefix == "" {
				return ""
			}
			prefix = prefix[:len(prefix)-1]
		}
	}
	return prefix
}

func parseAntigravity(body []byte) (*string, []rawMeter, [][2]string, error) {
	var resp struct {
		Buckets []struct {
			ModelID           string   `json:"modelId"`
			RemainingFraction *float64 `json:"remainingFraction"`
			ResetTime         string   `json:"resetTime"`
		} `json:"buckets"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, nil, nil, err
	}

	// Buckets share quota pools; group models with identical usage and
	// reset time into one meter instead of listing every model.
	type groupKey struct {
		pct   float64
		reset string
	}
	groups := map[groupKey][]string{}
	var order []groupKey
	for _, b := range resp.Buckets {
		if b.ModelID == "" || strings.HasPrefix(b.ModelID, "chat_") || strings.HasPrefix(b.ModelID, "tab_") {
			continue // internal models, not user-facing quota
		}
		pct := 0.0
		if b.RemainingFraction != nil {
			pct = (1 - *b.RemainingFraction) * 100
		}
		key := groupKey{pct: math.Round(pct*1e4) / 1e4, reset: b.ResetTime}
		if _, seen := groups[key]; !seen {
			order = append(order, key)
		}
		groups[key] = append(groups[key], b.ModelID)
	}

	meters := make([]rawMeter, 0, len(order))
	for _, key := range order {
		models := groups[key]
		var label string
		if prefix := commonPrefix(models); len(models) > 1 && prefix != "" {
			label = fmt.Sprintf("%s* (%d)", prefix, len(models))
		} else if len(models) > 1 {
			label = fmt.Sprintf("%s +%d", models[0], len(models)-1)
		} else {
			label = models[0]
		}
		meters = append(meters, rawMeter{label: label, pct: key.pct, reset: parseTime(key.reset)})
	}
	sort.SliceStable(meters, func(i, j int) bool { return meters[i].pct > meters[j].pct })
	return nil, meters, nil, nil
}

func parseOpencodeGo(body []byte) (*string, []rawMeter, [][2]string, error) {
	var resp struct {
		Usage json.RawMessage `json:"usage"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, nil, nil, err
	}
	// Decode the usage object as a stream to preserve the JSON key order
	// (Go maps would randomize it).
	var meters []rawMeter
	dec := json.NewDecoder(bytes.NewReader(resp.Usage))
	if _, err := dec.Token(); err != nil { // opening brace
		return nil, nil, nil, err
	}
	for dec.More() {
		tok, err := dec.Token()
		if err != nil {
			return nil, nil, nil, err
		}
		label := tok.(string)
		var usage map[string]any
		if err := dec.Decode(&usage); err != nil {
			return nil, nil, nil, err
		}
		name := label
		if name == "rolling" {
			name = "5-hour"
		}
		pct, _ := toFloat(usage["percent"])
		meters = append(meters, rawMeter{label: name, pct: pct, reset: parseTime(usage["resetsAt"])})
	}
	return nil, meters, nil, nil
}

// --- provider endpoint specs ---

type requestSpec struct {
	Method    string            `json:"method"`
	URL       string            `json:"url"`
	Header    map[string]string `json:"header"`
	Body      string            `json:"body,omitempty"`
	AuthIndex string            `json:"authIndex"`
}

type providerSpec struct {
	request   requestSpec
	fallbacks []string
	parse     parseFunc
}

var providerSpecs = map[string]providerSpec{
	"kimi": {
		request: requestSpec{
			Method: "GET",
			URL:    "https://api.kimi.com/coding/v1/usages",
			Header: map[string]string{"Authorization": "Bearer $TOKEN$"},
		},
		parse: parseKimi,
	},
	"codex": {
		request: requestSpec{
			Method: "GET",
			URL:    "https://chatgpt.com/backend-api/wham/usage",
			Header: map[string]string{"Authorization": "Bearer $TOKEN$"},
		},
		parse: parseCodex,
	},
	"antigravity": {
		// The quota endpoint 403s (a misleading "no valid license" error)
		// unless the request carries an Antigravity User-Agent. The daily
		// (staging) endpoint works the same way; fall back to production
		// on 403/404.
		request: requestSpec{
			Method: "POST",
			URL:    "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota",
			Header: map[string]string{
				"Authorization": "Bearer $TOKEN$",
				"Content-Type":  "application/json",
				"User-Agent":    "antigravity/hub/1.15.8 darwin/arm64",
			},
			Body: "{}",
		},
		fallbacks: []string{
			"https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota",
		},
		parse: parseAntigravity,
	},
}

// providerOrder fixes output ordering (Go maps don't iterate in order).
var providerOrder = []string{"kimi", "codex", "antigravity"}

// --- HTTP plumbing ---

type apiResponse struct {
	StatusCode int64  `json:"status_code"`
	Body       string `json:"body"`
}

func apiCall(client *http.Client, key string, payload requestSpec) apiResponse {
	data, err := json.Marshal(payload)
	if err != nil {
		return apiResponse{StatusCode: 0, Body: err.Error()}
	}
	req, err := http.NewRequest(http.MethodPost, mgmt+"/api-call", bytes.NewReader(data))
	if err != nil {
		return apiResponse{StatusCode: 0, Body: err.Error()}
	}
	req.Header.Set("Authorization", "Bearer "+key)
	req.Header.Set("Content-Type", "application/json")
	resp, err := client.Do(req)
	if err != nil {
		return apiResponse{StatusCode: 0, Body: err.Error()}
	}
	defer resp.Body.Close()
	var out apiResponse
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return apiResponse{StatusCode: 0, Body: err.Error()}
	}
	return out
}

type authFile struct {
	Name      string `json:"name"`
	Provider  string `json:"provider"`
	Disabled  bool   `json:"disabled"`
	AuthIndex string `json:"auth_index"`
}

func listAuthFiles(client *http.Client, key string) ([]authFile, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, mgmt+"/auth-files", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+key)
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	var out struct {
		Files []authFile `json:"files"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, err
	}
	return out.Files, nil
}

func fetchUsageInsights(client *http.Client, key, url string) (*UsageInsights, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+key)
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return nil, fmt.Errorf("HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	var out UsageInsights
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, err
	}
	return &out, nil
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}

func buildAccount(name string, resp apiResponse, parse parseFunc, now time.Time) Account {
	acct := Account{
		Name:   name,
		Meters: []Meter{},
		Notes:  [][2]string{},
	}
	if resp.StatusCode != 200 {
		msg := fmt.Sprintf("HTTP %d: %s", resp.StatusCode, truncate(resp.Body, 200))
		acct.Error = &msg
		return acct
	}
	subtitle, meters, notes, err := parse([]byte(resp.Body))
	if err != nil {
		msg := "invalid response body"
		acct.Error = &msg
		return acct
	}
	acct.Subtitle = subtitle
	acct.Meters = finalizeMeters(meters, now)
	if notes != nil {
		acct.Notes = notes
	}
	return acct
}

func fetchProxyAccount(client *http.Client, key string, spec providerSpec, f authFile, now time.Time) Account {
	urls := append([]string{spec.request.URL}, spec.fallbacks...)
	var resp apiResponse
	for _, url := range urls {
		req := spec.request
		req.URL = url
		req.AuthIndex = f.AuthIndex
		resp = apiCall(client, key, req)
		if resp.StatusCode != 403 && resp.StatusCode != 404 {
			break
		}
	}
	return buildAccount(f.Name, resp, spec.parse, now)
}

func fetchOpencodeGo(client *http.Client, key string, now time.Time) *Provider {
	if key == "" {
		return nil
	}
	req, err := http.NewRequest(http.MethodGet, opencodeUsageURL, nil)
	var resp apiResponse
	if err != nil {
		resp = apiResponse{StatusCode: 0, Body: err.Error()}
	} else {
		req.Header.Set("Authorization", "Bearer "+key)
		req.Header.Set("User-Agent", "opencode/ai-quota")
		httpResp, err := client.Do(req)
		if err != nil {
			resp = apiResponse{StatusCode: 0, Body: err.Error()}
		} else {
			defer httpResp.Body.Close()
			var buf bytes.Buffer
			_, _ = buf.ReadFrom(httpResp.Body)
			resp = apiResponse{StatusCode: int64(httpResp.StatusCode), Body: buf.String()}
		}
	}
	return &Provider{
		Provider: "opencode-go",
		Accounts: []Account{buildAccount("OpenCode Go", resp, parseOpencodeGo, now)},
	}
}

// --- human-readable rendering ---

func quotaLine(m Meter) string {
	pct := math.Min(math.Max(m.Pct, 0), 100)
	filled := int(math.Round(float64(barWidth) * pct / 100))
	graph := ""
	if filled > 0 {
		graph += paint(strings.Repeat("━", filled), usageColor(pct))
	}
	if empty := barWidth - filled; empty > 0 {
		graph += paint(strings.Repeat("─", empty), dim)
	}

	note := ""
	if m.ResetHuman != nil && m.ResetLocal != nil {
		note = paint(fmt.Sprintf("  resets in %s · %s", *m.ResetHuman, *m.ResetLocal), dim)
	}
	return fmt.Sprintf("%s  %s%s", graph, paint(fmt.Sprintf("%3.0f%%", pct), usageColor(pct)), note)
}

func accountDisplayName(acct Account) string {
	if acct.Subtitle != nil && *acct.Subtitle != "" {
		return *acct.Subtitle
	}

	name := strings.TrimSuffix(acct.Name, ".json")
	for _, prefix := range []string{"antigravity-", "codex-", "kimi-"} {
		name = strings.TrimPrefix(name, prefix)
	}
	return name
}

func printAccount(acct Account) {
	fmt.Println("  " + paint("●", cyan) + " " + paint(accountDisplayName(acct), bold))
	if acct.Error != nil {
		fmt.Println("    " + paint("error: "+*acct.Error, red))
		return
	}

	labelWidth := 0
	for _, m := range acct.Meters {
		if len(m.Label) <= 14 && len(m.Label) > labelWidth {
			labelWidth = len(m.Label)
		}
	}
	for _, n := range acct.Notes {
		if len(n[0]) <= 14 && len(n[0]) > labelWidth {
			labelWidth = len(n[0])
		}
	}

	for _, m := range acct.Meters {
		if len(m.Label) > 14 {
			fmt.Println("    " + paint(m.Label, dim))
			fmt.Println("      " + quotaLine(m))
			continue
		}
		fmt.Println("    " + paint(fmt.Sprintf("%-*s", labelWidth, m.Label), dim) + "  " + quotaLine(m))
	}
	for _, n := range acct.Notes {
		if len(n[0]) > 14 {
			fmt.Println("    " + paint(n[0], dim))
			fmt.Println("      " + n[1])
			continue
		}
		fmt.Println("    " + paint(fmt.Sprintf("%-*s", labelWidth, n[0]), dim) + "  " + n[1])
	}
}

func compactCount(n int64) string {
	value := float64(n)
	for _, unit := range []struct {
		suffix string
		scale  float64
	}{
		{"B", 1e9},
		{"M", 1e6},
		{"K", 1e3},
	} {
		if math.Abs(value) >= unit.scale {
			return strings.TrimRight(strings.TrimRight(fmt.Sprintf("%.2f", value/unit.scale), "0"), ".") + unit.suffix
		}
	}
	return strconv.FormatInt(n, 10)
}

func formatCostUSD(cost float64) string {
	precision := 2
	if math.Abs(cost) < 1 {
		precision = 4
	}
	if math.Abs(cost) < 0.01 {
		precision = 6
	}
	formatted := fmt.Sprintf("%.*f", precision, cost)
	for strings.Contains(formatted, ".") && strings.HasSuffix(formatted, "0") && len(formatted)-strings.LastIndex(formatted, ".")-1 > 2 {
		formatted = strings.TrimSuffix(formatted, "0")
	}
	return "$" + formatted
}

func usagePeriodLabel(period UsagePeriod) string {
	to, err := time.Parse(time.RFC3339Nano, period.To)
	if err != nil {
		return ""
	}
	if period.From == "1970-01-01T00:00:00Z" {
		return "lifetime · through " + to.UTC().Format("2006-01-02 15:04 UTC")
	}
	from, err := time.Parse(time.RFC3339Nano, period.From)
	if err != nil {
		return "through " + to.UTC().Format("2006-01-02 15:04 UTC")
	}
	return fmt.Sprintf("%s → %s UTC", from.UTC().Format("2006-01-02 15:04"), to.UTC().Format("2006-01-02 15:04"))
}

func aggregateUsage(models []ModelUsage) UsageAggregate {
	var total UsageAggregate
	for _, model := range models {
		total.APICalls += model.APICalls
		total.FailedAPICalls += model.FailedAPICalls
		total.InputTokens += model.InputTokens
		total.CacheReadTokens += model.CacheReadTokens
		total.CacheWriteTokens += model.CacheWriteTokens
		total.OutputTokens += model.OutputTokens
		total.TotalTokens += model.TotalTokens
		total.CostUSD += model.CostUSD
		total.PricedAPICalls += model.PricedAPICalls
		total.UnpricedAPICalls += model.UnpricedAPICalls
	}
	if input := total.InputTokens + total.CacheReadTokens; input > 0 {
		total.CacheHitRate = float64(total.CacheReadTokens) / float64(input)
	}
	return total
}

func callCount(calls int64) string {
	word := "calls"
	if calls == 1 {
		word = "call"
	}
	return fmt.Sprintf("%d %s", calls, word)
}

func printModelUsage(model ModelUsage) {
	callSummary := callCount(model.APICalls)
	if model.FailedAPICalls > 0 {
		callSummary += " · " + paint(fmt.Sprintf("%d failed", model.FailedAPICalls), red)
	}
	if model.UnpricedAPICalls > 0 {
		callSummary += " · " + paint(fmt.Sprintf("%d unpriced", model.UnpricedAPICalls), yellow)
	}

	fmt.Println("    " + paint(model.Model, bold) + "  " + callSummary + " · " + formatCostUSD(model.CostUSD))
	fmt.Printf("      %s tokens · %s input · %s output\n",
		compactCount(model.TotalTokens), compactCount(model.InputTokens), compactCount(model.OutputTokens))

	if model.CacheReadTokens > 0 || model.CacheWriteTokens > 0 {
		cache := "cache " + compactCount(model.CacheReadTokens) + " read"
		if model.CacheWriteTokens > 0 {
			cache += " · " + compactCount(model.CacheWriteTokens) + " write"
		}
		cache += fmt.Sprintf(" · %.1f%% hit", model.CacheHitRate*100)
		fmt.Println("      " + paint(cache, dim))
	}
}

func printUsage(models []ModelUsage, period UsagePeriod) {
	models = append([]ModelUsage(nil), models...)
	sort.SliceStable(models, func(i, j int) bool {
		if models[i].CostUSD != models[j].CostUSD {
			return models[i].CostUSD > models[j].CostUSD
		}
		if models[i].APICalls != models[j].APICalls {
			return models[i].APICalls > models[j].APICalls
		}
		return models[i].Model < models[j].Model
	})

	heading := "  " + paint("Usage", bold)
	if periodLabel := usagePeriodLabel(period); periodLabel != "" {
		heading += "  " + paint(periodLabel, dim)
	}
	fmt.Println(heading)
	for i, model := range models {
		if i > 0 {
			fmt.Println()
		}
		printModelUsage(model)
	}
	if len(models) > 1 {
		total := aggregateUsage(models)
		fmt.Println()
		fmt.Println("    " + paint(fmt.Sprintf("Total  %s · %s tokens · %s", callCount(total.APICalls), compactCount(total.TotalTokens), formatCostUSD(total.CostUSD)), bold))
	}
}

func main() {
	mgmtKey := loadKey("MGMT_KEY", "MGMT_KEY_FILE", defaultKeyFile)
	opencodeKey := loadKey("OPENCODE_API_KEY", "OPENCODE_API_KEY_FILE", defaultOCKeyFile)
	now := time.Now()

	client := &http.Client{Timeout: 30 * time.Second}

	// All fetches are blocking HTTP I/O; fan them out so wall time is the
	// slowest request rather than the sum.
	type ocResult struct{ provider *Provider }
	ocCh := make(chan ocResult, 1)
	go func() { ocCh <- ocResult{fetchOpencodeGo(client, opencodeKey, now)} }()

	type usageResult struct {
		insights *UsageInsights
		err      error
	}
	var usageCh chan usageResult
	if mgmtKey != "" {
		usageCh = make(chan usageResult, 1)
		go func() {
			insights, err := fetchUsageInsights(client, mgmtKey, usageInsightsURL)
			usageCh <- usageResult{insights, err}
		}()
	}

	var providers []Provider
	if mgmtKey != "" {
		files, err := listAuthFiles(client, mgmtKey)
		if err != nil {
			fmt.Fprintf(os.Stderr, "error: failed to list proxy auth files: %s\n", err)
			os.Exit(1)
		}
		type task struct {
			provider string
			file     authFile
		}
		var tasks []task
		for _, f := range files {
			if _, ok := providerSpecs[f.Provider]; ok && !f.Disabled {
				tasks = append(tasks, task{f.Provider, f})
			}
		}
		accounts := make([]Account, len(tasks))
		var wg sync.WaitGroup
		for i, t := range tasks {
			wg.Add(1)
			go func() {
				defer wg.Done()
				accounts[i] = fetchProxyAccount(client, mgmtKey, providerSpecs[t.provider], t.file, now)
			}()
		}
		wg.Wait()

		byProvider := map[string][]Account{}
		for i, t := range tasks {
			byProvider[t.provider] = append(byProvider[t.provider], accounts[i])
		}
		for _, name := range providerOrder {
			if accts, ok := byProvider[name]; ok {
				providers = append(providers, Provider{Provider: name, Accounts: accts})
			}
		}
	}

	if oc := (<-ocCh).provider; oc != nil {
		providers = append(providers, *oc)
	}

	var usageInsights *UsageInsights
	if usageCh != nil {
		result := <-usageCh
		if result.err != nil {
			fmt.Fprintf(os.Stderr, "warning: failed to fetch model usage insights: %s\n", result.err)
		} else {
			usageInsights = result.insights
		}
	}
	if len(providers) == 0 && (usageInsights == nil || len(usageInsights.Models) == 0) {
		fmt.Fprintln(os.Stderr, "No configured accounts with a known quota endpoint or model usage found.")
		os.Exit(1)
	}

	jsonOut := false
	for _, arg := range os.Args[1:] {
		if arg == "--json" {
			jsonOut = true
		}
	}
	if jsonOut {
		out, _ := json.Marshal(struct {
			Providers     []Provider     `json:"providers"`
			UsageInsights *UsageInsights `json:"usage_insights,omitempty"`
		}{providers, usageInsights})
		fmt.Println(string(out))
		return
	}

	usageByProvider := map[string][]ModelUsage{}
	if usageInsights != nil {
		for _, model := range usageInsights.Models {
			usageByProvider[model.Provider] = append(usageByProvider[model.Provider], model)
		}
	}

	printed := map[string]bool{}
	sections := 0
	for _, entry := range providers {
		if sections > 0 {
			fmt.Println()
		}
		fmt.Println(paint(strings.ToUpper(entry.Provider), bold, magenta))
		for i, acct := range entry.Accounts {
			if i > 0 {
				fmt.Println()
			}
			printAccount(acct)
		}
		if models := usageByProvider[entry.Provider]; len(models) > 0 {
			fmt.Println()
			printUsage(models, usageInsights.Period)
		}
		printed[entry.Provider] = true
		sections++
	}

	var usageOnly []string
	for provider := range usageByProvider {
		if !printed[provider] {
			usageOnly = append(usageOnly, provider)
		}
	}
	sort.Strings(usageOnly)
	for _, provider := range usageOnly {
		if sections > 0 {
			fmt.Println()
		}
		fmt.Println(paint(strings.ToUpper(provider), bold, magenta))
		printUsage(usageByProvider[provider], usageInsights.Period)
		sections++
	}
}
