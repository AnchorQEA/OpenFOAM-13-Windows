// Standalone UCRT/Win32 probe: no OpenFOAM headers or global state required.
#include "windowsRuntime.H"
#include <cstdlib>
#include <iostream>

namespace
{
const std::string selectedBeforeMain = Foam::windowsRuntime::startup().casePath;
std::string expected(const char* name)
{
    const char* value = std::getenv(name);
    return value ? value : "";
}
}

int main(int argc, char** argv)
{
    const auto& startup = Foam::windowsRuntime::startup();
    if (startup.rawArguments != std::vector<std::string>(argv, argv + argc))
    {
        std::cerr << "Early tokenization differs from UCRT argv\n";
        return 1;
    }
    if (startup.casePath != expected("TEST_CASE_PATH")
     || startup.casePath != selectedBeforeMain
     || startup.informational != (expected("TEST_INFORMATIONAL") == "1")
     || startup.error.empty() != (expected("TEST_ERROR") != "1")
     || Foam::windowsRuntime::bundledEtc() != expected("TEST_ETC_PATH"))
    {
        std::cerr << "Incorrect startup selection: " << startup.casePath
            << "; info=" << startup.informational << "; error=" << startup.error
            << "; etc=" << Foam::windowsRuntime::bundledEtc() << '\n';
        return 1;
    }
    std::cout << "NATIVE_STARTUP_OK\n";
}
