// regex_win.cpp - Windows ICU backend for AutoHotkey's RegEx.
//
// AutoHotkey's regex.cpp talks to PCRE through a small set of pcret_* (=pcre16_*)
// entry points.  When the build selects the "windows" regex backend, lib_pcre is
// NOT linked; this file supplies those same entry points, implemented on top of
// the ICU regex engine that ships in Windows 10 1903+ / Windows 11 (icu.dll,
// via <icu.h> and icu.lib from the Windows SDK).  regex.cpp itself is unchanged,
// so RegExMatch/RegExReplace, the match object, named groups and options letters
// all keep working - the pattern is just executed by the OS engine instead of a
// bundled copy of PCRE, which removes ~150 KB from the binary.
//
// Not emulated (ICU has no equivalent): callouts (?C), recursion (?R)/subroutines,
// the (?U) ungreedy option letter, DFA mode, and PCRE study/JIT.  Patterns that
// rely on those get a clear compile error, matching how ICU already rejects them.

#ifdef REGEX_BACKEND_WINDOWS

#define PCRE_STATIC
#include "lib_pcre/pcre/pcre.h"   // constants, option bits, pcre16 types (header only; no PCRE code is linked)

#include <icu.h>                  // Windows SDK: OS ICU (uregex_*, UChar = char16_t)
#include <string>
#include <vector>
#include <cstring>

// AHK's Unicode build uses wchar_t (UTF-16); ICU's UChar is char16_t.  Same width
// on Windows, distinct types, so bridge with reinterpret_cast.
static const UChar *U(const wchar_t *p) { return reinterpret_cast<const UChar *>(p); }

namespace {

struct NameEntry { std::wstring name; int number; };

// One compiled pattern.  Returned to regex.cpp as an opaque pcre16*.
struct WinRe
{
    URegularExpression *re = nullptr;
    int captureCount = 0;
    int compileOptions = 0;
    std::vector<NameEntry> names;
    int nameEntrySize = 0;                 // stride in UChars: 1 (number) + maxNameLen + 1 (null)
    std::vector<wchar_t> nameTable;        // PCRE16 NAMETABLE layout, built lazily
};

// Translate a PCRE pattern to the equivalent ICU pattern and, in the same pass,
// enumerate capturing groups so we can answer PCRE_INFO_NAME* the way regex.cpp
// expects.  Handles the named-group spellings ICU doesn't accept.
void TranslatePattern(const wchar_t *pat, std::wstring &out, std::vector<NameEntry> &names, int &captureCount)
{
    captureCount = 0;
    auto readName = [](const wchar_t *s, wchar_t close, std::wstring &name) -> int {
        int i = 0;
        while (s[i] && s[i] != close) { name += s[i]; ++i; }
        return i; // chars consumed, not counting the closer
    };

    for (const wchar_t *p = pat; *p; )
    {
        wchar_t c = *p;
        if (c == L'\\')
        {
            // Escape: copy verbatim, but normalise named backrefs to ICU's \k<name>.
            wchar_t n = p[1];
            if (n == L'k' && (p[2] == L'\'' || p[2] == L'{'))
            {
                wchar_t close = (p[2] == L'\'') ? L'\'' : L'}';
                std::wstring name;
                int used = readName(p + 3, close, name);
                out += L"\\k<"; out += name; out += L'>';
                p += 3 + used + (p[3 + used] ? 1 : 0);
                continue;
            }
            out += c; if (n) { out += n; p += 2; } else ++p;
            continue;
        }
        if (c == L'[')
        {
            // Character class: copy verbatim to the matching ']'.
            out += c; ++p;
            if (*p == L'^') { out += *p; ++p; }
            if (*p == L']') { out += *p; ++p; } // literal ] as first member
            while (*p && *p != L']')
            {
                if (*p == L'\\' && p[1]) { out += *p; out += p[1]; p += 2; }
                else { out += *p; ++p; }
            }
            if (*p == L']') { out += *p; ++p; }
            continue;
        }
        if (c == L'(')
        {
            if (p[1] == L'?')
            {
                // (?P<name>...) / (?P=name) / (?P>name)
                if (p[2] == L'P' && p[3] == L'<')
                {
                    std::wstring name; int used = readName(p + 4, L'>', name);
                    names.push_back({ name, ++captureCount });
                    out += L"(?<"; out += name; out += L'>';
                    p += 4 + used + 1;
                    continue;
                }
                if (p[2] == L'P' && p[3] == L'=')
                {
                    std::wstring name; int used = readName(p + 4, L')', name);
                    out += L"\\k<"; out += name; out += L'>';
                    p += 4 + used + 1;
                    continue;
                }
                // (?<name>...)  but NOT lookbehind (?<= / (?<!
                if (p[2] == L'<' && p[3] != L'=' && p[3] != L'!')
                {
                    std::wstring name; int used = readName(p + 3, L'>', name);
                    names.push_back({ name, ++captureCount });
                    out += L"(?<"; out += name; out += L'>';
                    p += 3 + used + 1;
                    continue;
                }
                // (?'name'...)
                if (p[2] == L'\'')
                {
                    std::wstring name; int used = readName(p + 3, L'\'', name);
                    names.push_back({ name, ++captureCount });
                    out += L"(?<"; out += name; out += L'>';
                    p += 3 + used + 1;
                    continue;
                }
                // Any other (?...) is non-capturing / assertion / inline flags.
                out += c; ++p;
                continue;
            }
            // Plain capturing group.
            ++captureCount;
            out += c; ++p;
            continue;
        }
        out += c; ++p;
    }
}

int TranslateOptions(int pcreOptions)
{
    int f = 0;
    if (pcreOptions & PCRE_CASELESS)  f |= UREGEX_CASE_INSENSITIVE;
    if (pcreOptions & PCRE_MULTILINE) f |= UREGEX_MULTILINE;
    if (pcreOptions & PCRE_DOTALL)    f |= UREGEX_DOTALL;
    if (pcreOptions & PCRE_EXTENDED)  f |= UREGEX_COMMENTS;
    return f;
}

void BuildNameTable(WinRe *r)
{
    if (r->names.empty()) { r->nameEntrySize = 0; return; }
    size_t maxLen = 0;
    for (auto &n : r->names) maxLen = (n.name.size() > maxLen) ? n.name.size() : maxLen;
    r->nameEntrySize = (int)(1 + maxLen + 1); // number + name + null, in UChars
    r->nameTable.assign(r->names.size() * r->nameEntrySize, 0);
    for (size_t i = 0; i < r->names.size(); ++i)
    {
        wchar_t *e = &r->nameTable[i * r->nameEntrySize];
        e[0] = (wchar_t)r->names[i].number;                 // pcre16: number in first code unit
        memcpy(e + 1, r->names[i].name.c_str(), (r->names[i].name.size() + 1) * sizeof(wchar_t));
    }
}

} // anonymous namespace

// --- PCRE ABI expected by regex.cpp -----------------------------------------

// Global callout hook (regex.cpp assigns &RegExCallout to it).  ICU never fires
// callouts, so this stays effectively unused but must exist for linking/assignment.
extern "C" int (*pcre16_callout)(pcre16_callout_block *) = nullptr;

extern "C" pcre16 *pcre16_compile2(PCRE_SPTR16 pattern, int options, int *errorcodeptr,
    const char **errorptr, int *erroroffset, const unsigned char *)
{
    WinRe *r = new WinRe();
    r->compileOptions = options;

    std::wstring icuPat;
    TranslatePattern(reinterpret_cast<const wchar_t *>(pattern), icuPat, r->names, r->captureCount);
    BuildNameTable(r);

    UErrorCode status = U_ZERO_ERROR;
    UParseError pe; memset(&pe, 0, sizeof(pe));
    r->re = uregex_open(U(icuPat.c_str()), (int32_t)icuPat.size(),
                        TranslateOptions(options), &pe, &status);
    if (U_FAILURE(status) || !r->re)
    {
        if (errorptr)     *errorptr = u_errorName(status);
        if (errorcodeptr) *errorcodeptr = (int)status;
        if (erroroffset)  *erroroffset = (pe.offset > 0) ? pe.offset : 0;
        delete r;
        return nullptr;
    }
    return reinterpret_cast<pcre16 *>(r);
}

extern "C" pcre16_extra *pcre16_study(const pcre16 *, int, const char **errptr)
{
    if (errptr) *errptr = nullptr;  // No study/JIT stage; NULL extra is valid to exec().
    return nullptr;
}

extern "C" void pcre16_free_study(pcre16_extra *) {}

// In PCRE, pcre16_free is the overridable allocator hook (a function-pointer
// variable), and freeing a compiled pattern means calling through it.  regex.cpp
// does exactly that, so provide it as a variable pointing at our destructor.
static void WinReFree(void *re)
{
    WinRe *r = reinterpret_cast<WinRe *>(re);
    if (!r) return;
    if (r->re) uregex_close(r->re);
    delete r;
}
extern "C" void (*pcre16_free)(void *) = &WinReFree;

extern "C" int pcre16_exec(const pcre16 *re, const pcre16_extra *extra, PCRE_SPTR16 subject,
    int length, int startoffset, int options, int *ovector, int ovecsize)
{
    WinRe *r = reinterpret_cast<WinRe *>(const_cast<pcre16 *>(re));
    if (!r || !r->re) return PCRE_ERROR_NOMATCH;

    // regex.cpp may pass a stack extra used only to receive (*MARK); ICU has none.
    if (extra && (extra->flags & PCRE_EXTRA_MARK) && extra->mark)
        *extra->mark = nullptr;

    UErrorCode status = U_ZERO_ERROR;
    uregex_setText(r->re, U(subject), length, &status);
    if (U_FAILURE(status)) return PCRE_ERROR_NOMATCH;

    UBool matched;
    if ((options & PCRE_ANCHORED) || (r->compileOptions & PCRE_ANCHORED))
        matched = uregex_lookingAt(r->re, startoffset, &status); // must match exactly at startoffset
    else
        matched = uregex_find(r->re, startoffset, &status);
    if (U_FAILURE(status) || !matched)
        return PCRE_ERROR_NOMATCH;

    int mStart = uregex_start(r->re, 0, &status);
    int mEnd   = uregex_end(r->re, 0, &status);
    if (U_FAILURE(status)) return PCRE_ERROR_NOMATCH;

    // Reject empty match when the caller forbids it (used to step past empty matches).
    if ((options & PCRE_NOTEMPTY) && mStart == mEnd)
        return PCRE_ERROR_NOMATCH;

    int groups = r->captureCount + 1;          // including whole-match group 0
    int pairs = ovecsize / 3;                  // PCRE reserves 3 ints per group
    int fill = (groups < pairs) ? groups : pairs;
    for (int i = 0; i < fill; ++i)
    {
        UErrorCode gs = U_ZERO_ERROR;
        int s = uregex_start(r->re, i, &gs);
        int e = uregex_end(r->re, i, &gs);
        if (U_FAILURE(gs)) { s = -1; e = -1; }  // group didn't participate
        ovector[2 * i]     = s;
        ovector[2 * i + 1] = e;
    }
    return (groups <= pairs) ? groups : 0;      // 0 = ovector too small (PCRE convention)
}

extern "C" int pcre16_fullinfo(const pcre16 *re, const pcre16_extra *, int what, void *where)
{
    WinRe *r = reinterpret_cast<WinRe *>(const_cast<pcre16 *>(re));
    if (!r) return -1;
    switch (what)
    {
    case PCRE_INFO_CAPTURECOUNT: *(int *)where = r->captureCount; return 0;
    case PCRE_INFO_NAMECOUNT:    *(int *)where = (int)r->names.size(); return 0;
    case PCRE_INFO_NAMEENTRYSIZE:*(int *)where = r->nameEntrySize; return 0;
    case PCRE_INFO_NAMETABLE:
        *(const wchar_t **)where = r->nameTable.empty() ? L"" : r->nameTable.data();
        return 0;
    case PCRE_INFO_OPTIONS:      *(int *)where = r->compileOptions; return 0;
    default:
        if (where) *(int *)where = 0;
        return 0;
    }
}

// AutoHotkey extension: number of the first set subpattern with the given name.
extern "C" int pcre16_get_first_set(const pcre16 *re, PCRE_SPTR16 name, int *ovector)
{
    WinRe *r = reinterpret_cast<WinRe *>(const_cast<pcre16 *>(re));
    if (!r) return PCRE_ERROR_NOSUBSTRING;
    const wchar_t *want = reinterpret_cast<const wchar_t *>(name);
    int only = -1, count = 0;
    for (auto &n : r->names)
        if (n.name == want)
        {
            ++count; only = n.number;
            if (ovector && ovector[2 * n.number] >= 0) return n.number; // first that participated
        }
    if (count == 1) return only;      // single name: return it even if unset
    return (count > 1) ? PCRE_ERROR_NOSUBSTRING : PCRE_ERROR_NOSUBSTRING;
}

#endif // REGEX_BACKEND_WINDOWS
