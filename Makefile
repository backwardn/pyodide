PYODIDE_ROOT=$(abspath .)
include Makefile.envs

PYVERSION=3.6.4
PYMINOR=$(basename $(PYVERSION))
CPYTHONROOT=cpython
CPYTHONLIB=$(CPYTHONROOT)/installs/python-$(PYVERSION)/lib/python$(PYMINOR)
CPYTHONINC=$(CPYTHONROOT)/installs/python-$(PYVERSION)/include/python$(PYMINOR)
HOSTPYTHON=$(CPYTHONROOT)/build/$(PYVERSION)/host/bin/python3

CC=emcc
CXX=em++
OPTFLAGS=-O3
CXXFLAGS=-std=c++14 $(OPTFLAGS) -g -I$(CPYTHONINC) -Wno-warn-absolute-paths
LDFLAGS=\
	-O3 \
	-s MODULARIZE=1 \
	$(CPYTHONROOT)/installs/python-$(PYVERSION)/lib/libpython$(PYMINOR).a \
  -s "BINARYEN_METHOD='native-wasm'" \
  -s TOTAL_MEMORY=268435456 \
	-s MAIN_MODULE=1 \
	-s EMULATED_FUNCTION_POINTERS=1 \
  -s EMULATE_FUNCTION_POINTER_CASTS=1 \
  -s EXPORTED_FUNCTIONS='["_main"]' \
  -s WASM=1 \
  --memory-init-file 0

NUMPY_ROOT=numpy/build/numpy
NUMPY_LIBS=\
	$(NUMPY_ROOT)/core/multiarray.so \
	$(NUMPY_ROOT)/core/umath.so \
	$(NUMPY_ROOT)/linalg/lapack_lite.so \
	$(NUMPY_ROOT)/linalg/_umath_linalg.so \
	$(NUMPY_ROOT)/random/mtrand.so \
	$(NUMPY_ROOT)/fft/fftpack_lite.so

PANDAS_ROOT=pandas/build/pandas
PANDAS_LIBS=\
	$(PANDAS_ROOT)/_libs/lib.so

SITEPACKAGES=root/lib/python$(PYMINOR)/site-packages

all: build/pyodide.asm.html build/pyodide.js build/pyodide_dev.js build/python.html


build/pyodide.asm.html: src/main.bc src/jsimport.bc src/jsproxy.bc src/js2python.bc \
                        src/pyimport.bc src/pyproxy.bc src/python2js.bc \
												src/runpython.bc root/.built
	[ -d build ] || mkdir build
	$(CC) -s EXPORT_NAME="'pyodide'" --bind -o $@ $(filter %.bc,$^) $(LDFLAGS) \
		$(foreach d,$(wildcard root/*),--preload-file $d@/$(notdir $d))
	sed -i -e "s#REMOTE_PACKAGE_BASE = 'pyodide.asm.data'#REMOTE_PACKAGE_BASE = pyodide.baseURL + 'pyodide.asm.data'#g" build/pyodide.asm.js


build/pyodide_dev.js: src/pyodide.js
	cp $< $@
	sed -i -e "s#{{DEPLOY}}##g" $@


build/pyodide.js: src/pyodide.js
	cp $< $@
	sed -i -e 's#{{DEPLOY}}#https://iodide-project.github.io/pyodide-demo/#g' $@


build/python.html: src/python.html
	cp $< $@


build/test.html: src/test.html
	cp $< $@


test: all build/test.html
	py.test test -v


benchmark: all build/test.html
	python benchmark/benchmark.py $(HOSTPYTHON) build/benchmarks.json
	python benchmark/plot_benchmark.py build/benchmarks.json build/benchmarks.png


clean:
	rm -fr root
	rm build/*
	rm src/*.bc
	echo "CPython and Numpy builds are not cleaned. cd into those directories to do so."


%.bc: %.cpp $(CPYTHONLIB)
	$(CXX) --bind -o $@ $< $(CXXFLAGS)


root/.built: \
		$(CPYTHONLIB) \
		$(NUMPY_LIBS) \
		$(PANDAS_LIBS) \
		src/lazy_import.py \
		src/sitecustomize.py \
		src/webbrowser.py \
		remove_modules.txt
	rm -rf root
	mkdir -p root/lib
	cp -a $(CPYTHONLIB)/ root/lib
	cp -a numpy/build/numpy $(SITEPACKAGES)
	cp -a pandas/build/pandas $(SITEPACKAGES)
	rm -fr $(SITEPACKAGES)/numpy/distutils
	cp src/lazy_import.py $(SITEPACKAGES)
	cp src/sitecustomize.py $(SITEPACKAGES)
	cp src/webbrowser.py root/lib/python$(PYMINOR)
	cp src/_testcapi.py	root/lib/python$(PYMINOR)
	cp src/pystone.py root/lib/python$(PYMINOR)
	( \
		cd root/lib/python$(PYMINOR); \
		rm -fr `cat ../../../remove_modules.txt`; \
		rm encodings/cp*.py; \
		rm encodings/mac_*.py; \
		find . -name "*.wasm.pre" -type f -delete ; \
		find -type d -name __pycache__ -prune -exec rm -rf {} \; \
	)
	touch root/.built


$(CPYTHONLIB): emsdk/emsdk/emsdk
	make -C $(CPYTHONROOT)


$(NUMPY_LIBS): $(CPYTHONLIB)
	make -C numpy

$(PANDAS_LIBS): $(NUMPY_LIBS)
	make -C pandas

emsdk/emsdk/emsdk:
	make -C emsdk
