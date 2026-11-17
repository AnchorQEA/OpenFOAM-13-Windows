#include "windowsRuntime.H"

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <algorithm>

namespace
{
bool space(wchar_t c)
{
    return c == L' ' || c == L'\t';
}

// Match UCRT argv quoting without calling shell APIs under the DLL loader lock.
std::vector<std::string> commandLine()
{
    const wchar_t* p = GetCommandLineW();
    std::vector<std::wstring> wide;
    std::wstring executable;
    bool quoted = false;
    while (*p && (quoted || !space(*p)))
    {
        if (*p == L'"') quoted = !quoted;
        else executable += *p;
        ++p;
    }
    wide.push_back(executable);
    while (*p)
    {
        while (space(*p)) ++p;
        if (!*p) break;
        std::wstring argument;
        quoted = false;
        while (*p && (quoted || !space(*p)))
        {
            unsigned slashes = 0;
            while (*p == L'\\') { ++slashes; ++p; }
            if (*p == L'"')
            {
                argument.append(slashes/2, L'\\');
                if (slashes % 2) argument += *p++;
                else if (quoted && p[1] == L'"')
                {
                    argument += L'"';
                    p += 2;
                }
                else { quoted = !quoted; ++p; }
            }
            else
            {
                argument.append(slashes, L'\\');
                if (!*p || (!quoted && space(*p))) break;
                argument += *p++;
            }
        }
        wide.push_back(argument);
    }

    std::vector<std::string> result;
    for (const auto& argument : wide)
    {
        // OpenFOAM's Windows file APIs and main's narrow argv use the ANSI page.
        const int size = WideCharToMultiByte
            (CP_ACP, 0, argument.c_str(), -1, nullptr, 0, nullptr, nullptr);
        std::vector<char> buffer(size);
        if (size) WideCharToMultiByte
            (CP_ACP, 0, argument.c_str(), -1, buffer.data(), size, nullptr, nullptr);
        result.push_back(size ? buffer.data() : "");
    }
    return result;
}

std::string absolutePath(const std::string& path)
{
    const DWORD size = GetFullPathNameA(path.c_str(), 0, nullptr, nullptr);
    if (!size) return "";
    std::vector<char> buffer(size);
    const DWORD length = GetFullPathNameA(path.c_str(), size, buffer.data(), nullptr);
    if (!length || length >= size) return "";
    std::string result(buffer.data());
    std::replace(result.begin(), result.end(), '\\', '/');
    while (result.size() > 3 && result.back() == '/') result.pop_back();
    return result;
}

Foam::windowsRuntime::Startup readStartup()
{
    Foam::windowsRuntime::Startup result;
    result.rawArguments = commandLine();
    result.arguments = Foam::windowsRuntime::groupArguments(result.rawArguments);
    std::string selected = ".";
    bool haveCase = false;
    for (std::size_t i = 1; i < result.arguments.size(); ++i)
    {
        const std::string& arg = result.arguments[i];
        if (arg == "-help" || arg == "--help" || arg == "-h"
         || arg == "-version" || arg == "--version" || arg == "-v"
         || arg == "-doc" || arg == "-srcDoc")
        {
            result.informational = true;
        }
        else if (arg == "-case" || arg == "-libs" || arg == "-fileHandler"
              || arg == "-roots" || arg == "-hostRoots")
        {
            if (i + 1 == result.arguments.size()
             || (!result.arguments[i + 1].empty() && result.arguments[i + 1][0] == '-'))
            {
                result.error = "Option '" + arg + "' requires an argument";
                continue;
            }
            const std::string& value = result.arguments[++i];
            if (arg == "-case" && !haveCase)
            {
                // HashTable::insert in argList preserves the first occurrence.
                selected = value.empty() ? "." : value;
                haveCase = true;
            }
        }
    }
    result.casePath = absolutePath(selected);
    if (result.casePath.empty() && result.error.empty())
    {
        result.error = "Cannot resolve case directory '" + selected + "'";
    }
    return result;
}
}

std::vector<std::string> Foam::windowsRuntime::groupArguments
(
    const std::vector<std::string>& arguments
)
{
    std::vector<std::string> result;
    std::string list;
    unsigned depth = 0;
    for (const auto& argument : arguments)
    {
        if (argument == "(") { ++depth; list += '('; }
        else if (argument == ")" && depth)
        {
            list += ')';
            if (!--depth) { result.push_back(list); list.clear(); }
        }
        else if (depth) list += '"' + argument + '"';
        else result.push_back(argument);
    }
    if (!list.empty()) result.push_back(list);
    return result;
}

const Foam::windowsRuntime::Startup& Foam::windowsRuntime::startup()
{
    static const Startup value = readStartup();
    return value;
}

std::string Foam::windowsRuntime::bundledEtc()
{
    HMODULE module = nullptr;
    if (!GetModuleHandleExW
    (
        GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS
      | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        reinterpret_cast<LPCWSTR>(&bundledEtc), &module
    )) return "";

    std::vector<char> buffer(32768);
    const DWORD length = GetModuleFileNameA(module, buffer.data(), buffer.size());
    if (!length || length >= buffer.size()) return "";
    const std::string path(buffer.data(), length);
    const auto separator = path.find_last_of("/\\");
    if (separator == std::string::npos) return "";
    return absolutePath(path.substr(0, separator) + "/../OpenFOAM-13/etc");
}
#endif
