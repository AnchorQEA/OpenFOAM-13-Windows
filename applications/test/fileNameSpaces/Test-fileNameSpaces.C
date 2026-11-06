/*---------------------------------------------------------------------------*\
  =========                 |
  \\      /  F ield         | OpenFOAM: The Open Source CFD Toolbox
   \\    /   O peration     | Website:  https://openfoam.org
    \\  /    A nd           | Copyright (C) 2026 Anchor QEA
     \\/     M anipulation  |
-------------------------------------------------------------------------------
License
    This file is part of OpenFOAM.

    OpenFOAM is free software: you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    OpenFOAM is distributed in the hope that it will be useful, but WITHOUT
    ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
    FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
    for more details.

    You should have received a copy of the GNU General Public License
    along with OpenFOAM.  If not, see <http://www.gnu.org/licenses/>.

Application
    Test-fileNameSpaces

Description
    Verify native Windows startup and file reading from paths containing spaces.

\*---------------------------------------------------------------------------*/

#include "argList.H"
#include "etcFiles.H"
#include "IFstream.H"
#include "IOstreams.H"
#include "OSspecific.H"

using namespace Foam;

int main(int argc, char *argv[])
{
    if (fileName::debug != 2)
    {
        Info<< "FAIL: require fileName debug level 2" << endl;
        return 1;
    }

    #if defined(_WIN32)
    if (!fileName::valid(' '))
    #else
    if (fileName::valid(' '))
    #endif
    {
        Info<< "FAIL: unexpected platform space policy" << endl;
        return 1;
    }

    for (const char invalid : {'\t', '\r', '\n', '\v', '\f', '\'', '"'})
    {
        if (fileName::valid(invalid))
        {
            Info<< "FAIL: accepted a prohibited filename character" << endl;
            return 1;
        }
    }

    // These copies also let us check the path conversion inside libOpenFOAM.
    const string executablePath(argv[0]);
    const string fixturePath(argc == 2 ? argv[1] : "");
    writeInfoHeader = false;
    argList::noParallel();
    argList::validArgs.append("fixture");
    argList args(argc, argv);

    if (args[0] != executablePath || args[1] != fixturePath)
    {
        Info<< "FAIL: argument parsing changed a path" << endl;
        return 1;
    }

    const fileName fixture(args[1]);
    const fileName config(findEtcFile("controlDict", true));
    const string expectedConfig = getEnv("WM_PROJECT_DIR") + "/etc/controlDict";
    if (fixture != fixturePath || config != expectedConfig)
    {
        Info<< "FAIL: filename conversion changed a fixture or configuration path"
            << endl;
        return 1;
    }

    IFstream input(fixture);
    word value;
    input >> value;
    if (input.bad() || input.fail() || value != "OPENFOAM_PATH_FIXTURE")
    {
        Info<< "FAIL: could not read the fixture" << endl;
        return 1;
    }

    Info<< "FILE_NAME_SPACES_OK" << endl;
    return 0;
}

// ************************************************************************* //
