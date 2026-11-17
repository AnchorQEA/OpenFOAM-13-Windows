/* Native startup information, available before OpenFOAM static initializers. */
#ifndef windowsRuntime_H
#define windowsRuntime_H

#ifdef _WIN32
#include <string>
#include <vector>

namespace Foam
{
namespace windowsRuntime
{
struct Startup
{
    std::vector<std::string> rawArguments;
    std::vector<std::string> arguments;
    std::string casePath;
    std::string error;
    bool informational = false;
};

// These functions must not depend on Foam objects, streams or debug switches.
const Startup& startup();
std::string bundledEtc();
std::vector<std::string> groupArguments(const std::vector<std::string>&);
}
}
#endif
#endif
