"""clausage MCP tests: stdlib unittest, no network beyond localhost, no real credentials.
Run: python3 -m unittest discover -s tests -v   (from mcp/)
"""
import http.server, io, json, os, plistlib, shutil, subprocess, sys, tempfile, threading, time, unittest
from contextlib import redirect_stderr, redirect_stdout
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
import server  # noqa: E402

SENTINEL = "sk-ant-oat-SENTINEL-DO-NOT-LEAK-123"


def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")


class FakeAPI(http.server.BaseHTTPRequestHandler):
    status, body, delay, hits, headers_seen = 200, b"{}", 0, 0, None

    def do_GET(self):
        FakeAPI.hits += 1
        FakeAPI.headers_seen = dict(self.headers)
        time.sleep(FakeAPI.delay)
        self.send_response(FakeAPI.status); self.end_headers(); self.wfile.write(FakeAPI.body)

    def log_message(self, *a):
        pass


class Base(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), FakeAPI)
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.creds = os.path.join(self.tmp, "creds.json")
        os.environ["CLAUSAGE_CREDENTIALS_FILE"] = self.creds
        server.HOME = os.path.join(self.tmp, "home")
        server.OAUTH_CACHE = os.path.join(server.HOME, "oauth-cache.json")
        server.JOBS_LOG = os.path.join(server.HOME, "jobs.jsonl")
        server.STATUSLINE_CACHE = os.path.join(server.HOME, "usage-latest.json")
        server.APP_PLIST = os.path.join(self.tmp, "app.plist")
        server.API_BASE = "http://127.0.0.1:%d" % self.httpd.server_port
        FakeAPI.status, FakeAPI.delay, FakeAPI.hits, FakeAPI.headers_seen = 200, 0, 0, None
        self.now = time.time()
        self.api({"five_hour": {"utilization": 40, "resets_at": iso(self.now + 3600)},
                  "seven_day": {"utilization": 50, "resets_at": iso(self.now + 3 * 86400)},
                  "seven_day_opus": None, "seven_day_sonnet": {"utilization": 20, "resets_at": iso(self.now + 3 * 86400)}})
        self.write_creds()

    def tearDown(self):
        shutil.rmtree(self.tmp)
        os.environ.pop("CLAUSAGE_CREDENTIALS_FILE", None)

    def api(self, obj, status=200):
        FakeAPI.body = obj if isinstance(obj, bytes) else json.dumps(obj).encode()
        FakeAPI.status = status

    def write_creds(self, token=SENTINEL, scopes=("user:inference", "user:profile"), expires_in=3600):
        o = {"claudeAiOauth": {"accessToken": token, "refreshToken": "r-" + SENTINEL,
                               "expiresAt": int((self.now + expires_in) * 1000), "scopes": list(scopes)}}
        with open(self.creds, "w") as f:
            json.dump(o, f)

    def write_app(self, age=60, **over):
        snap = {"connected": True, "updated": iso(self.now - age), "limits": [
            {"kind": "session", "percent": 10, "resetsAt": iso(self.now + 7200), "shortTitle": "Session"},
            {"kind": "weekly_all", "percent": 93, "resetsAt": iso(self.now + 86400), "shortTitle": "Weekly · All"},
            {"kind": "weekly_scoped", "percent": 76, "resetsAt": iso(self.now + 86400), "shortTitle": "Weekly · Fable"}]}
        snap.update(over)
        with open(server.APP_PLIST, "wb") as f:
            plistlib.dump({"snapshot": json.dumps(snap).encode()}, f)

    def write_statusline(self, age=30, used=33):
        os.makedirs(server.HOME, exist_ok=True)
        with open(server.STATUSLINE_CACHE, "w") as f:
            json.dump({"at": self.now - age, "rate_limits": {
                "five_hour": {"used_percentage": used, "resets_at": self.now + 1000}}}, f)


class TestOAuth(Base):
    def test_ok_maps_utilization_and_headers(self):
        s = server.snapshot()
        self.assertEqual(s["source"], "oauth")
        self.assertEqual(s["limits"]["session"]["used_percent"], 40)
        self.assertEqual(s["limits"]["week"]["used_percent"], 50)
        self.assertEqual(s["limits"]["week_sonnet"]["used_percent"], 20)
        self.assertNotIn("week_opus", s["limits"])  # null window skipped
        h = {k.lower(): v for k, v in FakeAPI.headers_seen.items()}
        self.assertEqual(h["authorization"], "Bearer " + SENTINEL)
        self.assertEqual(h["anthropic-beta"], "oauth-2025-04-20")
        self.assertTrue(h["user-agent"].startswith("clausage-mcp/"))

    def test_limits_array_shape(self):
        self.api({"limits": [
            {"kind": "session", "percent": 11, "resets_at": iso(self.now + 3600)},
            {"kind": "weekly_all", "percent": 93, "resets_at": iso(self.now + 86400)},
            {"kind": "weekly_scoped", "percent": 76, "resets_at": iso(self.now + 86400),
             "scope": {"model": {"display_name": "Fable"}}},
            {"kind": "weekly_scoped", "percent": 5, "scope": None},
            {"kind": "mystery", "percent": 1}],
            "seven_day_breakdown": {"utilization": 99}, "seven_day_oauth_apps": {"utilization": 3, "resets_at": None}})
        s = server.snapshot()["limits"]
        self.assertEqual((s["session"]["used_percent"], s["week"]["used_percent"]), (11, 93))
        self.assertEqual(s["week_fable"]["used_percent"], 76)
        self.assertEqual(s["week_scoped"]["used_percent"], 5)
        self.assertEqual(s["week_oauth_apps"]["used_percent"], 3)
        self.assertNotIn("week_breakdown", s)
        r = server.check_job({"size": "small"})
        self.assertEqual(r["verdict"], "caution")  # week_fable 76 + 0.4 fine, week 93.4 -> caution

    def test_ttl_cache_skips_network(self):
        server.snapshot(); server.snapshot()
        self.assertEqual(FakeAPI.hits, 1)

    def test_cache_file_private_and_tokenless(self):
        server.snapshot()
        self.assertEqual(os.stat(server.OAUTH_CACHE).st_mode & 0o777, 0o600)
        self.assertNotIn(SENTINEL, open(server.OAUTH_CACHE).read())

    def test_429_backs_off(self):
        self.api({}, 429)
        s = server.snapshot()
        self.assertIn("HTTP 429", s["sources"]["oauth"])
        server.snapshot()
        self.assertEqual(FakeAPI.hits, 1)  # second call did not hit the endpoint

    def test_failures_fall_through_to_app(self):
        self.write_app()
        for status, body in [(401, b"{}"), (500, b"{}"), (200, b"not json"), (200, b"[1,2]")]:
            with self.subTest(status=status, body=body):
                if os.path.exists(server.OAUTH_CACHE):
                    os.remove(server.OAUTH_CACHE)
                self.api(body, status)
                s = server.snapshot()
                self.assertEqual(s["source"], "app")
                self.assertIn("oauth", s["skipped_sources"])

    def test_timeout_falls_through(self):
        self.write_statusline()
        FakeAPI.delay = 6
        t = time.time(); s = server.snapshot()
        self.assertLess(time.time() - t, 10)
        self.assertEqual(s["source"], "statusline")
        FakeAPI.delay = 0

    def test_non_subscriber_empty_body(self):
        self.api({})
        s = server.snapshot()
        self.assertIn("no plan limits", s["sources"]["oauth"])

    def test_credentials_problems(self):
        cases = [("expired", dict(expires_in=10), "expired"),
                 ("scope", dict(scopes=("user:inference",)), "user:profile"),
                 ("no token", dict(token=None), "no OAuth token")]
        for name, kw, msg in cases:
            with self.subTest(name):
                self.write_creds(**kw)
                self.assertIn(msg, server.snapshot()["sources"]["oauth"])
        os.remove(self.creds)
        self.assertIn("no Claude Code login", server.snapshot()["sources"]["oauth"])
        open(self.creds, "w").write("garbage")
        self.assertIn("unreadable", server.snapshot()["sources"]["oauth"])
        self.assertEqual(FakeAPI.hits, 0)

    def test_keychain_stub(self):
        """macOS path: `security` failing (exit 44) falls back to the credentials file location."""
        os.environ.pop("CLAUSAGE_CREDENTIALS_FILE")
        bindir = os.path.join(self.tmp, "bin"); os.makedirs(bindir)
        stub = os.path.join(bindir, "security")
        open(stub, "w").write("#!/bin/sh\nexit 44\n"); os.chmod(stub, 0o755)
        env = {"PATH": bindir + os.pathsep + os.environ["PATH"], "CLAUDE_CONFIG_DIR": self.tmp}
        old = {k: os.environ.get(k) for k in env}
        os.environ.update(env)
        try:
            shutil.copy(self.creds, os.path.join(self.tmp, ".credentials.json"))
            self.assertEqual(server.read_credentials(), SENTINEL)
            os.remove(os.path.join(self.tmp, ".credentials.json"))
            with self.assertRaises(server.SourceError):
                server.read_credentials()
        finally:
            for k, v in old.items():
                os.environ.pop(k, None) if v is None else os.environ.__setitem__(k, v)


class TestApp(Base):
    def setUp(self):
        super().setUp()
        os.remove(self.creds)  # force past oauth

    def test_fresh(self):
        self.write_app()
        s = server.snapshot()
        self.assertEqual(s["source"], "app")
        self.assertEqual(s["limits"]["session"]["used_percent"], 10)
        self.assertEqual(s["limits"]["week"]["used_percent"], 93)
        self.assertEqual(s["limits"]["week_fable"]["used_percent"], 76)
        self.assertEqual(s["limits"]["week"]["status"], "warn")

    def test_rejected(self):
        for name, kw in [("stale", dict(age=3600)), ("sample", dict(sample="x")),
                         ("cleared", dict(cleared=True)), ("disconnected", dict(connected=False))]:
            with self.subTest(name):
                self.write_app(**kw)
                self.assertIn("app", server.snapshot()["sources"])

    def test_missing_and_garbage(self):
        self.assertIn("not installed", server.snapshot()["sources"]["app"])
        open(server.APP_PLIST, "wb").write(b"garbage")
        self.assertIn("unreadable", server.snapshot()["sources"]["app"])


class TestHistory(Base):
    def setUp(self):
        super().setUp()
        server.APP_HISTORY_DIR = os.path.join(self.tmp, "History")

    def week(self, start, pcts, step=3600):
        return {"start": start, "resetsAt": start + 7 * 86400, "samples": len(pcts),
                "readings": [{"t": start + 60 + i * step, "pct": p} for i, p in enumerate(pcts)]}

    def write(self, plist_weeks, archive_weeks=None, keep=None):
        d = {"weeklyHistory": json.dumps({"weeks": plist_weeks, "owner": "org"}).encode()}
        if keep is not None:
            d["historyWeeks"] = keep
        with open(server.APP_PLIST, "wb") as f:
            plistlib.dump(d, f)
        if archive_weeks is not None:
            os.makedirs(server.APP_HISTORY_DIR, exist_ok=True)
            with open(os.path.join(server.APP_HISTORY_DIR, "weeklyHistory.json"), "w") as f:
                json.dump({"weeks": archive_weeks, "owner": "org"}, f)

    def test_last_week_and_days(self):
        cur = self.now - 86400
        last = self.week(cur - 7 * 86400, [10, 30, 55, 95], step=86400)
        self.write([last, self.week(cur, [0, 4])])
        h = server.history({})
        self.assertEqual(h["weeks_available"], 2)
        now_w, last_w = h["weeks"]
        self.assertTrue(now_w["current"]); self.assertIn("resets_in", now_w)
        self.assertEqual(now_w["so_far_percent"], 4)
        self.assertFalse(last_w["current"]); self.assertNotIn("resets_at", last_w)
        self.assertEqual(last_w["final_percent"], 95)
        self.assertEqual([d["used_percent"] for d in last_w["days"]], [10, 20, 25, 40])
        self.assertEqual(h["kept_weeks"], 2)

    def test_archive_merges_and_limit(self):
        base = self.now - 30 * 86400
        old = [self.week(base, [50]), self.week(base + 7 * 86400, [60])]
        recent = [self.week(base + 14 * 86400, [70]), self.week(base + 21 * 86400, [80])]
        self.write(recent, archive_weeks=old + [self.week(base + 14 * 86400, [1])], keep=13)
        h = server.history({"weeks": 3})
        self.assertEqual(h["weeks_available"], 4)
        self.assertEqual([w["final_percent"] for w in h["weeks"]], [80, 70, 60])  # plist wins over archive
        self.assertEqual(h["kept_weeks"], 13)
        self.assertEqual(server.history({"weeks": "junk"})["weeks"][0]["final_percent"], 80)

    def test_early_reset_day(self):
        start = self.now - 10 * 86400
        self.write([self.week(start, [40, 60, 5, 12], step=600)])
        day = server.history({})["weeks"][0]["days"]
        self.assertTrue(any(d.get("early_reset") for d in day))
        self.assertTrue(all(d["used_percent"] >= 0 for d in day))

    def test_late_start_note(self):
        start = self.now - 10 * 86400
        w = self.week(start, [20, 30])
        for r in w["readings"]:
            r["t"] += 3 * 86400
        self.write([w])
        self.assertIn("recording started", server.history({})["weeks"][0]["note"])

    def test_missing_and_garbage(self):
        self.assertIn("No usage history", server.history({})["error"])
        with open(server.APP_PLIST, "wb") as f:
            plistlib.dump({"weeklyHistory": b"garbage"}, f)
        self.assertIn("error", server.history({}))


class TestAppContract(Base):
    """The app side of these files is generated by Tests/MCPContractTests.swift from the app's real encoders."""
    FIX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")

    def fixture(self, name):
        with open(os.path.join(self.FIX, name), "rb") as f:
            return f.read()

    def setUp(self):
        super().setUp()
        os.remove(self.creds)  # force past oauth
        server.APP_HISTORY_DIR = os.path.join(self.tmp, "History")

    def test_keys(self):
        k = json.loads(self.fixture("app-keys.json"))
        self.assertEqual(server.APP_GROUP, k["macGroupID"])
        self.assertEqual(server.SNAPSHOT_KEY, k["snapshotKey"])
        self.assertEqual(server.HISTORY_KEY, k["historyKey"])
        self.assertEqual(server.RETENTION_KEY, k["retentionKey"])
        self.assertEqual(server.ARCHIVE_DIR, k["archiveDir"])
        self.assertEqual(server.HISTORY_KEY + ".json", k["archiveFile"])

    def test_snapshot(self):
        snap = json.loads(self.fixture("app-snapshot.json"))
        snap["updated"] = iso(self.now - 60)  # the golden's date is fixed; src_app wants a fresh one
        with open(server.APP_PLIST, "wb") as f:
            plistlib.dump({server.SNAPSHOT_KEY: json.dumps(snap).encode()}, f)
        rl = server.src_app()["rate_limits"]
        self.assertEqual({k: v["used_percentage"] for k, v in rl.items()},
                         {"five_hour": 10, "seven_day": 93, "seven_day_fable": 76})
        self.assertEqual(server._ts(rl["five_hour"]["resets_at"]), server._ts("2026-09-21T16:13:20Z"))

    def test_history(self):
        with open(server.APP_PLIST, "wb") as f:
            plistlib.dump({server.HISTORY_KEY: self.fixture("app-weekly-history.json")}, f)
        w = server.history({})["weeks"][0]
        self.assertEqual(w["final_percent"], 95)
        self.assertEqual(w["readings"], 4)
        self.assertEqual([d["used_percent"] for d in w["days"]], [10, 20, 25, 40])


class TestStatusline(Base):
    def setUp(self):
        super().setUp()
        os.remove(self.creds)

    def test_fresh_and_stale(self):
        self.write_statusline()
        self.assertEqual(server.snapshot()["source"], "statusline")
        self.write_statusline(age=3600)
        self.assertIn("older", server.snapshot()["sources"]["statusline"])

    def test_all_fail_lists_reasons(self):
        s = server.snapshot()
        self.assertEqual(set(s["sources"]), {"oauth", "app", "statusline"})


class TestCheckJob(Base):
    def verdict(self, session, week, **args):
        self.api({"five_hour": {"utilization": session, "resets_at": iso(self.now + 3600)},
                  "seven_day": {"utilization": week, "resets_at": iso(self.now + 86400)}})
        if os.path.exists(server.OAUTH_CACHE):
            os.remove(server.OAUTH_CACHE)
        return server.check_job(args)

    def test_table(self):
        cases = [(10, 10, {"size": "small"}, "go"),
                 (60, 10, {"size": "large"}, "caution"),
                 (80, 10, {"size": "large"}, "wait"),
                 (10, 95, {"size": "overnight"}, "stop"),
                 (80, 95, {"size": "large"}, "stop"),
                 (10, 10, {"estimate_session_percent": 95}, "wait"),
                 (10, 10, {}, "go")]
        for s, w, args, want in cases:
            with self.subTest(session=s, week=w, args=args):
                r = self.verdict(s, w, **args)
                self.assertEqual(r["verdict"], want, r["notes"])

    def test_reset_shown_in_notes(self):
        r = self.verdict(80, 10, size="large")
        self.assertIn("resets", r["notes"][0])

    def test_error_passthrough(self):
        os.remove(self.creds)
        self.assertIn("error", server.check_job({}))
        self.assertFalse(os.path.exists(server.JOBS_LOG))

    def test_jobs_logged(self):
        os.environ["CLAUDE_CODE_SESSION_ID"] = "sess-1"
        try:
            self.verdict(60, 10, size="large", description="refactor")
            self.verdict(10, 10, estimate_session_percent=5)
        finally:
            os.environ.pop("CLAUDE_CODE_SESSION_ID")
        lines = [json.loads(l) for l in open(server.JOBS_LOG)]
        self.assertEqual(len(lines), 2)
        a, b = lines
        self.assertEqual((a["session_id"], a["size"], a["estimate_session_percent"], a["verdict"]), ("sess-1", "large", 30, "caution"))
        self.assertEqual(a["description"], "refactor")
        self.assertEqual(a["used"], {"session": 60.0, "week": 10.0})
        self.assertEqual(b["estimate_session_percent"], 5)
        self.assertEqual(os.stat(server.JOBS_LOG).st_mode & 0o777, 0o600)
        self.assertNotIn(SENTINEL, open(server.JOBS_LOG).read())


class TestNoLeak(Base):
    def test_sentinel_never_leaks(self):
        """Every failure path: token never in tool output, stderr, or cache."""
        paths = [(b"{}", 401), (b"x", 200), (b"{}", 429), (json.dumps({"error": SENTINEL}).encode(), 500)]
        for body, status in paths:
            with self.subTest(status=status):
                for f in (server.OAUTH_CACHE,):
                    if os.path.exists(f):
                        os.remove(f)
                self.api(body, status)
                out, err = io.StringIO(), io.StringIO()
                with redirect_stdout(out), redirect_stderr(err):
                    res = server.handle({"method": "tools/call", "params": {"name": "check_job", "arguments": {}}})
                blob = json.dumps(res) + out.getvalue() + err.getvalue()
                if os.path.exists(server.OAUTH_CACHE):
                    blob += open(server.OAUTH_CACHE).read()
                self.assertNotIn("SENTINEL", blob)


class TestProtocol(Base):
    def run_server(self, *lines, args=()):
        env = {**os.environ, "CLAUSAGE_HOME": server.HOME, "CLAUSAGE_APP_PLIST": server.APP_PLIST,
               "CLAUSAGE_API_BASE": server.API_BASE, "CLAUSAGE_CREDENTIALS_FILE": self.creds}
        p = subprocess.run([sys.executable, os.path.join(ROOT, "server.py"), *args], input="\n".join(lines) + "\n",
                           capture_output=True, text=True, env=env, timeout=30)
        return p

    def test_stdio_roundtrip(self):
        p = self.run_server(
            json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18"}}),
            json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}),
            "not json",
            json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/list"}),
            json.dumps({"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "check_job", "arguments": {"size": "large"}}}),
            json.dumps({"jsonrpc": "2.0", "id": 4, "method": "nope"}))
        r = [json.loads(l) for l in p.stdout.splitlines()]
        self.assertEqual(len(r), 5)  # notification gets no reply; parse error does
        self.assertIn("check_job", r[0]["result"]["instructions"])
        self.assertEqual(r[1]["error"]["code"], -32700)
        self.assertEqual({t["name"] for t in r[2]["result"]["tools"]}, {"get_usage", "check_job", "get_history"})
        body = json.loads(r[3]["result"]["content"][0]["text"])
        self.assertEqual(body["source"], "oauth"); self.assertEqual(body["verdict"], "go")
        self.assertEqual(r[4]["error"]["code"], -32601)
        self.assertNotIn("SENTINEL", p.stdout + p.stderr)

    def test_check_cli(self):
        p = self.run_server(args=["--check"])
        self.assertEqual(p.returncode, 0); self.assertIn("OK via oauth", p.stdout)
        os.remove(self.creds); os.remove(server.OAUTH_CACHE)
        p = self.run_server(args=["--check"])
        self.assertEqual(p.returncode, 1); self.assertIn("No usage source", p.stdout)


class TestInstaller(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.home = os.path.join(self.tmp, "home"); os.makedirs(os.path.join(self.home, ".claude"))
        self.bin = os.path.join(self.tmp, "bin"); os.makedirs(self.bin)
        self.log = os.path.join(self.tmp, "claude.log")
        open(os.path.join(self.bin, "claude"), "w").write(f'#!/bin/sh\necho "$*" >> {self.log}\n')
        os.chmod(os.path.join(self.bin, "claude"), 0o755)
        sec = os.path.join(self.bin, "security"); open(sec, "w").write("#!/bin/sh\nexit 44\n"); os.chmod(sec, 0o755)
        self.settings = os.path.join(self.home, ".claude", "settings.json")
        json.dump({"statusLine": {"type": "command", "command": "echo MINE"}, "other": 1}, open(self.settings, "w"))

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def sh(self, *args):
        env = {"HOME": self.home, "PATH": self.bin + os.pathsep + os.environ["PATH"]}
        return subprocess.run(["sh", os.path.join(ROOT, "install.sh"), *args], capture_output=True, text=True, env=env, timeout=30)

    def test_default_install_leaves_settings(self):
        before = open(self.settings).read()
        p = self.sh()
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(open(self.settings).read(), before)
        self.assertTrue(os.path.exists(os.path.join(self.home, ".clausage-mcp", "server.py")))
        self.assertIn("mcp add -s user clausage -- python3", open(self.log).read())
        self.assertIn("no source yet", p.stdout)  # self-check ran, no creds in fake HOME

    def test_statusline_optin_and_uninstall(self):
        self.assertEqual(self.sh("--statusline").returncode, 0)
        s = json.load(open(self.settings))
        self.assertTrue(s["statusLine"]["command"].endswith(".clausage-mcp/statusline.sh"))
        self.assertEqual(s["other"], 1)
        p = subprocess.run(["sh", s["statusLine"]["command"]], input=json.dumps({"rate_limits": {"five_hour": {"used_percentage": 5}}}),
                           capture_output=True, text=True, env={"HOME": self.home, "PATH": os.environ["PATH"]})
        self.assertEqual(p.stdout.strip(), "MINE")
        self.assertIn("five_hour", open(os.path.join(self.home, ".clausage-mcp", "usage-latest.json")).read())
        self.assertEqual(self.sh("--statusline").returncode, 0)  # re-run keeps the original
        self.assertEqual(self.sh("uninstall").returncode, 0)
        s = json.load(open(self.settings))
        self.assertEqual(s["statusLine"]["command"], "echo MINE")
        self.assertFalse(os.path.exists(os.path.join(self.home, ".clausage-mcp")))


if __name__ == "__main__":
    unittest.main()
