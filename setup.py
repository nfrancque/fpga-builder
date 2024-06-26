"""Python setup.py for project_name package"""
import io
import os
from setuptools import find_packages, setup


def read(*paths, **kwargs):
    """Read the contents of a text file safely.
    >>> read("project_name", "VERSION")
    '0.1.0'
    >>> read("README.md")
    ...
    """

    content = ""
    with io.open(
        os.path.join(os.path.dirname(__file__), *paths),
        encoding=kwargs.get("encoding", "utf8"),
    ) as open_file:
        content = open_file.read().strip()
    return content


def read_requirements(path):
    return [
        line.strip()
        for line in read(path).split("\n")
        if not line.startswith(('"', "#", "-", "git+"))
    ]


packages = find_packages(exclude=["tests", ".github"])
print(packages)

setup(
    name="fpga_builder",
    version=read("VERSION"),
    description="project_description",
    # url="https://github.com/author_name/project_urlname/",
    long_description=read("README.md"),
    long_description_content_type="text/markdown",
    author="author_name",
    packages=packages,
    install_requires=read_requirements("requirements.txt"),
    entry_points={"console_scripts": ["project_name = project_name.__main__:main"]},
    package_data={"fpga_builder": ["utils.tcl"]},
    include_package_data=True
    # extras_require={"test": read_requirements("requirements-test.txt")},
)
