from distutils.core import setup
from distutils.extension import Extension

from Cython.Build import cythonize
from numpy import get_include

setup(
    name="nlpg",
    ext_modules=cythonize(
        Extension(
            "nlpg.extract_tags",
            ["./nlpg/extract_tags.pyx"],
            include_dirs=[".", get_include()],
            language="c++",
        ),
        language_level=3,
    ),
)
