#!/usr/bin/env python3
"""Converts an Adblock Plus list (EasyList and friends) into WebKit content blocker rules.

    python3 tools/easylist-to-webkit.py easylist.txt ContentBlocker/easylist.json

tools/update-blocking-lists.sh does this for every list the app ships. The JSON is used by the
Safari content blocker extension (the in-app Safari sheet) and compiled with
WKContentRuleListStore for the built-in browser.

Covers the bulk of the list: network rules with domain anchors, wildcards, separators, the
third-party, domain and resource type options, exceptions, and element hiding (generic and
per site, with per-site exceptions). Skipped: regular expression rules, extended CSS
(#?#, :-abp-…, :has-text…), and options WebKit can't express ($csp, $redirect, $removeparam…).

EasyList is by The EasyList authors (https://easylist.to/), CC BY-SA 3.0 / GPL 3.
"""
import json
import re
import sys

RESOURCE_TYPES = {
    "script": ["script"],
    "image": ["image"],
    "stylesheet": ["style-sheet"],
    "font": ["font"],
    "media": ["media"],
    "xmlhttprequest": ["raw"],
    "subdocument": ["document"],
    "ping": ["ping"],
    "websocket": ["raw"],
    "object": ["media"],
    "other": ["raw"],
    "popup": ["popup"],
}
ALL_TYPES = sorted({t for types in RESOURCE_TYPES.values() for t in types if t != "popup"})
# Options that only refine or don't change what's blocked.
HARMLESS_OPTIONS = {"important", "match-case"}

# Extended CSS that WebKit doesn't understand; one bad selector voids a whole merged rule.
UNSUPPORTED_SELECTOR = re.compile(
    r":-abp-|:has-text|:contains|:xpath|:matches-|:upward|:remove|:style|:min-text-length|:watch-attr|:others|:if|\[-ext-|:nth-ancestor|:matches-path"
)
GENERIC_CHUNK = 250


def domain_list(value, separator):
    """`a.com|~b.com` → (["*a.com"], ["*b.com"]); None if a domain can't be used."""
    included, excluded = [], []
    for domain in value.split(separator):
        domain = domain.strip().lower()
        negated = domain.startswith("~")
        domain = domain.lstrip("~")
        if not domain or not domain.isascii() or "*" in domain or "/" in domain:
            return None
        (excluded if negated else included).append("*" + domain)
    return included, excluded


def url_filter(pattern):
    """Adblock Plus pattern → WebKit's regular expression subset (no alternation)."""
    regex = ""
    if pattern.startswith("||"):
        regex = r"^[htpsw]+:\/\/([a-z0-9-]+\.)?"
        pattern = pattern[2:]
        domain_anchor = True
    else:
        domain_anchor = False
        if pattern.startswith("|"):
            regex = "^"
            pattern = pattern[1:]
    end_anchor = pattern.endswith("|")
    if end_anchor:
        pattern = pattern[:-1]

    # Where the host ends, for `||host^`.
    host_end = None
    if domain_anchor:
        match = re.match(r"[a-z0-9.\-]+", pattern)
        host_end = match.end() if match else None

    for index, char in enumerate(pattern):
        if char == "*":
            regex += ".*"
        elif char == "^":
            last = index == len(pattern) - 1
            if index == host_end:
                regex += "[/:]"
            elif last:
                pass  # "separator or end": dropped, matching a little more
            else:
                regex += "[/:?&=]"
        elif char in r".+?()[]{}\$|":
            regex += "\\" + char
        else:
            regex += char
    if end_anchor:
        regex += "$"
    if regex.startswith(".*"):
        regex = regex[2:]
    return regex or ".*"


def network_rule(line):
    exception = line.startswith("@@")
    if exception:
        line = line[2:]
    pattern, _, options_text = line.rpartition("$") if "$" in line else (line, "", "")
    if len(pattern) > 1 and pattern.startswith("/") and pattern.endswith("/"):
        return None, None  # Regular expression rule.
    if not pattern and not options_text:
        return None, None
    trigger = {"url-filter": url_filter(pattern)}
    types, excluded_types = [], []
    special = None
    for option in filter(None, options_text.split(",")):
        negated = option.startswith("~")
        name, _, value = option.lstrip("~").partition("=")
        if name == "third-party":
            trigger["load-type"] = ["first-party" if negated else "third-party"]
        elif name == "domain":
            domains = domain_list(value, "|")
            if domains is None:
                return None, None
            included, excluded = domains
            if included:
                trigger["if-domain"] = included
            elif excluded:
                trigger["unless-domain"] = excluded
        elif name in RESOURCE_TYPES:
            (excluded_types if negated else types).extend(RESOURCE_TYPES[name])
        elif name in ("document", "elemhide", "generichide") and exception:
            special = name
        elif name in HARMLESS_OPTIONS:
            pass
        else:
            return None, None
    if types:
        trigger["resource-type"] = sorted(set(types))
    elif excluded_types:
        trigger["resource-type"] = [t for t in ALL_TYPES if t not in excluded_types]

    if special:
        # Whole-site exceptions: everything on pages of that site.
        site = re.match(r"^\|\|([a-z0-9.\-]+)\^?$", pattern)
        if not site:
            return None, None
        exception_trigger = {"url-filter": ".*", "if-domain": ["*" + site.group(1)]}
        kind = "document" if special == "document" else "generichide"
        return kind, {"trigger": exception_trigger, "action": {"type": "ignore-previous-rules"}}
    action = {"type": "ignore-previous-rules" if exception else "block"}
    return ("allow" if exception else "block"), {"trigger": trigger, "action": action}


def convert(lines):
    generic_selectors = []
    generic_exceptions = {}  # selector → domains where it's not hidden
    site_hiding = []
    blocks, allows, generichide, documents = [], [], [], []
    skipped = 0

    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("!") or line.startswith("["):
            continue
        if "#?#" in line or "#$#" in line or "#%#" in line or "#@?#" in line:
            skipped += 1
            continue
        if "#@#" in line:
            domains, selector = line.split("#@#", 1)
            if domains and not UNSUPPORTED_SELECTOR.search(selector):
                parsed = domain_list(domains, ",")
                if parsed and parsed[0]:
                    generic_exceptions.setdefault(selector, []).extend(parsed[0])
                    continue
            skipped += 1
            continue
        if "##" in line:
            domains, selector = line.split("##", 1)
            if UNSUPPORTED_SELECTOR.search(selector) or not selector:
                skipped += 1
                continue
            if not domains:
                generic_selectors.append(selector)
                continue
            parsed = domain_list(domains, ",")
            if parsed is None:
                skipped += 1
                continue
            included, excluded = parsed
            trigger = {"url-filter": ".*"}
            if included:
                trigger["if-domain"] = included
            elif excluded:
                trigger["unless-domain"] = excluded
            site_hiding.append({"trigger": trigger, "action": {"type": "css-display-none", "selector": selector}})
            continue

        kind, rule = network_rule(line)
        if rule is None:
            skipped += 1
        else:
            {"block": blocks, "allow": allows, "generichide": generichide, "document": documents}[kind].append(rule)

    # Generic hiding, merged into big selector lists; selectors with site exceptions on their own.
    generic = []
    plain = [s for s in dict.fromkeys(generic_selectors) if s not in generic_exceptions]
    for start in range(0, len(plain), GENERIC_CHUNK):
        generic.append({
            "trigger": {"url-filter": ".*"},
            "action": {"type": "css-display-none", "selector": ", ".join(plain[start:start + GENERIC_CHUNK])},
        })
    for selector in dict.fromkeys(generic_selectors):
        if selector in generic_exceptions:
            generic.append({
                "trigger": {"url-filter": ".*", "unless-domain": sorted(set(generic_exceptions[selector]))},
                "action": {"type": "css-display-none", "selector": selector},
            })

    # Order matters: ignore-previous-rules only undoes the rules above it.
    rules = generic + generichide + blocks + allows + site_hiding + documents
    return rules, skipped


def main():
    source, destination = sys.argv[1], sys.argv[2]
    with open(source, encoding="utf-8") as file:
        rules, skipped = convert(file)
    if len(rules) > 150_000:
        sys.exit(f"{len(rules)} rules: over WebKit's limit of 150,000")
    with open(destination, "w", encoding="utf-8") as file:
        json.dump(rules, file, separators=(",", ":"))
    print(f"{len(rules)} rules written, {skipped} lines skipped", file=sys.stderr)


if __name__ == "__main__":
    main()
