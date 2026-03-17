from distutils.core import setup
from distutils.extension import Extension
from Cython.Build import cythonize
from numpy import get_include


def make_ext():
    """Make the Cython extension."""

    return Extension(
        "nlpg.extract_tags",
        ["./nlpg/extract_tags.pyx"],
        include_dirs=[".", get_include()],
        language="c++",
    )


setup(
    name="nlpg",
    ext_modules=cythonize(make_ext(), language_level=3),
)
