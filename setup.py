# setup.py
from setuptools import setup
from Cython.Build import cythonize
import numpy

setup(
    ext_modules=cythonize("FastCamera.pyx"),
    include_dirs=[numpy.get_include()]
)

# python setup.py build_ext --inplace