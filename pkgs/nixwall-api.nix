{python3Packages}:
python3Packages.buildPythonPackage {
  pname = "nixwall-api";
  version = "0.1.0";
  src = ../api;

  pyproject = true;

  nativeBuildInputs = with python3Packages; [
    setuptools
    wheel
  ];

  propagatedBuildInputs = with python3Packages; [
    fastapi
    uvicorn
  ];

  pythonImportsCheck = ["nixwall_api"];
}
