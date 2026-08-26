// Fetch quota for direct subscriptions and accounts on the tailnet AI proxy.
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
	defaultKeyFile   = "~/.secrets/ai-proxy-mgmt-key"
	defaultOCKeyFile = "~/.secrets/opencode-api-key"
	opencodeUsageURL = "https://opencode.ai/zen/go/v1/usage"

	barWidth = 20
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
	if pct >= 80 {
		return red
	}
	if pct >= 50 {
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
	filled := int(math.RoundToEven(barWidth * pct / 100))
	graph := paint(strings.Repeat("█", filled), usageColor(pct)) +
		paint(strings.Repeat("░", barWidth-filled), dim)
	note := ""
	if m.ResetHuman != nil && m.ResetLocal != nil {
		note = paint(fmt.Sprintf(" · resets in %s (%s)", *m.ResetHuman, *m.ResetLocal), dim)
	}
	return fmt.Sprintf("%s %.0f%% used%s", graph, pct, note)
}

func printAccount(acct Account) {
	var rows []string
	if acct.Error != nil {
		rows = append(rows, paint("error: "+*acct.Error, red))
	} else {
		var labels []string
		if acct.Subtitle != nil {
			labels = append(labels, "user")
		}
		for _, m := range acct.Meters {
			labels = append(labels, m.Label)
		}
		for _, n := range acct.Notes {
			labels = append(labels, n[0])
		}
		width := 0
		for _, l := range labels {
			if len(l) > width {
				width = len(l)
			}
		}
		if acct.Subtitle != nil {
			rows = append(rows, paint(fmt.Sprintf("%-*s", width, "user"), dim)+" "+*acct.Subtitle)
		}
		for _, m := range acct.Meters {
			rows = append(rows, paint(fmt.Sprintf("%-*s", width, m.Label), dim)+" "+quotaLine(m))
		}
		for _, n := range acct.Notes {
			rows = append(rows, paint(fmt.Sprintf("%-*s", width, n[0]), dim)+" "+n[1])
		}
	}
	fmt.Println("  " + paint("● ", cyan) + paint(acct.Name, bold))
	for _, r := range rows {
		fmt.Println("    " + r)
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
	if len(providers) == 0 {
		fmt.Fprintln(os.Stderr, "No configured accounts with a known quota endpoint found.")
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
			Providers []Provider `json:"providers"`
		}{providers})
		fmt.Println(string(out))
		return
	}

	for i, entry := range providers {
		if i > 0 {
			fmt.Println()
		}
		fmt.Println(paint(entry.Provider, bold, magenta))
		for _, acct := range entry.Accounts {
			printAccount(acct)
		}
	}
}
