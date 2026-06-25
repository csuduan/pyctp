# Minimal setuptools shim required to force platform-specific wheel tags.
#
# The ctpx package ships pre-compiled .so/.dylib/.dll/.pyd binaries inside
# package-data. setuptools only emits a platform-specific wheel tag when it
# knows the distribution contains C extensions. Without this hook, the wheel
# would be incorrectly tagged as py3-none-any, which cannot be installed on
# platforms that require native extensions.
#
# Once setuptools supports inferring platform tags from package-data binaries,
# this file can be removed.
from setuptools import setup

setup(
    has_ext_modules=lambda: True,
)
