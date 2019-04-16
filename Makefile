# This file is renamed to "Makefile.ext" in release tarballs so that setup.py won't try to
# run it.  If you want setup.py to run "make" automatically, rename it back to "Makefile".

# The pyvenv multiple runtime support is based on https://github.com/DRMacIver/hypothesis/blob/master/Makefile

PYTHON?=python${TRAVIS_PYTHON_VERSION}
CYTHON?=cython
BUILD_RUNTIMES?=$(PWD)/.runtimes


export PATH:=$(BUILD_RUNTIMES)/snakepit:$(PATH)
export LC_ALL=C.UTF-8
export GEVENT_RESOLVER_NAMESERVERS=8.8.8.8


clean:
	rm -f src/gevent/libev/corecext.c src/gevent/libev/corecext.h
	rm -f src/gevent/resolver/cares.c src/gevent/resolver/cares.h
	rm -f src/gevent/_semaphore.c src/gevent/_semaphore.h
	rm -f src/gevent/local.c src/gevent/local.h
	rm -f src/gevent/*.so src/gevent/*.pyd src/gevent/libev/*.so src/gevent/libuv/*.so src/gevent/libev/*.pyd src/gevent/libuv/*.pyd
	rm -rf src/gevent/libev/*.o src/gevent/libuv/*.o src/gevent/*.o
	rm -rf src/gevent/__pycache__ src/greentest/__pycache__ src/greentest/greentest/__pycache__ src/gevent/libev/__pycache__
	rm -rf src/gevent/*.pyc src/greentest/*.pyc src/gevent/libev/*.pyc
	rm -rf htmlcov .coverage
	rm -rf build

distclean: clean
	rm -rf dist
	rm -rf deps/libev/config.h deps/libev/config.log deps/libev/config.status deps/libev/.deps deps/libev/.libs
	rm -rf deps/c-ares/config.h deps/c-ares/config.log deps/c-ares/config.status deps/c-ares/.deps deps/c-ares/.libs

doc:
	cd doc && PYTHONPATH=.. make html


prospector:
	which pylint
	pylint --rcfile=.pylintrc gevent
# debugging
#	pylint --rcfile=.pylintrc --init-hook="import sys, code; sys.excepthook = lambda exc, exc_type, tb: print(tb.tb_next.tb_next.tb_next.tb_next.tb_next.tb_next.tb_next.tb_next.tb_next.tb_next.tb_frame.f_locals['self'])" gevent src/greentest/* || true
# XXX: prospector is failing right now. I can't reproduce locally:
# https://travis-ci.org/gevent/gevent/jobs/345474139
#	${PYTHON} scripts/gprospector.py -X

lint: prospector

test_prelim:
	@which ${PYTHON}
	@${PYTHON} --version
	@${PYTHON} -c 'import greenlet; print(greenlet, greenlet.__version__)'
	@${PYTHON} -c 'import gevent.core; print(gevent.core.loop)'
	@${PYTHON} -c 'import gevent.ares; print(gevent.ares)'
	@make bench

# Folding from https://github.com/travis-ci/travis-rubies/blob/9f7962a881c55d32da7c76baefc58b89e3941d91/build.sh#L38-L44

basictest: test_prelim
	@${PYTHON} scripts/travis.py fold_start basictest "Running basic tests"
	GEVENT_RESOLVER=thread ${PYTHON} -mgevent.tests --config known_failures.py --quiet
	@${PYTHON} scripts/travis.py fold_end basictest

alltest: basictest
	@${PYTHON} scripts/travis.py fold_start ares "Running c-ares tests"
	GEVENT_RESOLVER=ares ${PYTHON} -mgevent.tests --config known_failures.py --ignore tests_that_dont_use_resolver.txt --quiet
	@${PYTHON} scripts/travis.py fold_end ares
	@${PYTHON} scripts/travis.py fold_start dnspython "Running dnspython tests"
	GEVENT_RESOLVER=dnspython ${PYTHON} -mgevent.tests --config known_failures.py --ignore tests_that_dont_use_resolver.txt --quiet
	@${PYTHON} scripts/travis.py fold_end dnspython
# In the past, we included all test files that had a reference to 'subprocess'' somewhere in their
# text. The monkey-patched stdlib tests were specifically included here.
# However, we now always also test on AppVeyor (Windows) which only has GEVENT_FILE=thread,
# so we can save a lot of CI time by reducing the set and excluding the stdlib tests without
# losing any coverage.
	@${PYTHON} scripts/travis.py fold_start thread "Running GEVENT_FILE=thread tests"
	cd src/gevent/tests && GEVENT_FILE=thread ${PYTHON} -mgevent.tests --config known_failures.py test__*subprocess*.py --quiet
	@${PYTHON} scripts/travis.py fold_end thread

allbackendtest:
	@${PYTHON} scripts/travis.py fold_start default "Testing default backend"
	GEVENTTEST_COVERAGE=1 make alltest
	@${PYTHON} scripts/travis.py fold_end default
	GEVENTTEST_COVERAGE=1 make cffibackendtest
# because we set parallel=true, each run produces new and different coverage files; they all need
# to be combined
	make coverage_combine


cffibackendtest:
	@${PYTHON} scripts/travis.py fold_start libuv "Testing libuv backend"
	GEVENT_LOOP=libuv make alltest
	@${PYTHON} scripts/travis.py fold_end libuv
	@${PYTHON} scripts/travis.py fold_start libev "Testing libev CFFI backend"
	GEVENT_LOOP=libev-cffi make alltest
	@${PYTHON} scripts/travis.py fold_end libev

leaktest: test_prelim
	@${PYTHON} scripts/travis.py fold_start leaktest "Running leak tests"
	GEVENT_RESOLVER=thread GEVENTTEST_LEAKCHECK=1 ${PYTHON} -mgevent.tests --config known_failures.py --quiet --ignore tests_that_dont_do_leakchecks.txt
	@${PYTHON} scripts/travis.py fold_end leaktest
	@${PYTHON} scripts/travis.py fold_start default "Testing default backend pure python"
	PURE_PYTHON=1 GEVENTTEST_COVERAGE=1 make basictest
	@${PYTHON} scripts/travis.py fold_end default

bench:
	time ${PYTHON} benchmarks/bench_sendall.py --loops 3 --processes 2 --values 2 --warmups 2 --quiet

travis_test_linters:
	make lint
	make leaktest
	make cffibackendtest

coverage_combine:
	${PYTHON} -m coverage combine .
	${PYTHON} -m coverage report -i
	-${PYTHON} -m coveralls


.PHONY: clean doc prospector lint travistest travis


develop:
	@echo python is at `which $(PYTHON)`
	ls -l ${BUILD_RUNTIMES}
	ls -l ${BUILD_RUNTIMES}/snakepit
	@${PYTHON} scripts/travis.py fold_start install "Installing gevent"
# First install a newer pip so that it can use the wheel cache
# (only needed until travis upgrades pip to 7.x; note that the 3.5
# environment uses pip 7.1 by default)
	${PYTHON} -m pip install -U pip setuptools
# Then start installing our deps so they can be cached. Note that use of --build-options / --global-options / --install-options
# disables the cache.
# We need wheel>=0.26 on Python 3.5. See previous revisions.
	GEVENTSETUP_EV_VERIFY=3 time ${PYTHON} -m pip install -U --upgrade-strategy=eager -r dev-requirements.txt
	${PYTHON} -m pip freeze
	ccache -s
	@${PYTHON} scripts/travis.py fold_end install

test-py27:
	PYTHON=python2.7 make develop leaktest cffibackendtest coverage_combine

test-py35:
	PYTHON=python3.5 make develop basictest

test-py36:
	PYTHON=python3.6 make develop lint basictest

test-py37:
	PYTHON=python3.7 make develop leaktest cffibackendtest coverage_combine

test-pypy:
	PYTHON=pypy2.7 make develop cffibackendtest

test-pypy3:
	PYTHON=pypy3.6 make develop basictest

test-py27-noembed:
	@python2.7 scripts/travis.py fold_start conf_libev "Configuring libev"
	cd deps/libev && ./configure --disable-dependency-tracking && make
	@python2.7 scripts/travis.py fold_end conf_libev
	@python2.7 scripts/travis.py fold_start conf_cares "Configuring cares"
	cd deps/c-ares && ./configure --disable-dependency-tracking && make
	@python2.7 scripts/travis.py fold_end conf_cares
	@python2.7 scripts/travis.py fold_start conf_libuv "Configuring libuv"
	cd deps/libuv && ./autogen.sh && ./configure --disable-static && make
	@python2.7 scripts/travis.py fold_end conf_libuv
	CPPFLAGS="-Ideps/libev -Ideps/c-ares -Ideps/libuv/include" LDFLAGS="-Ldeps/libev/.libs -Ldeps/c-ares/.libs -Ldeps/libuv/.libs" LD_LIBRARY_PATH="$(PWD)/deps/libev/.libs:$(PWD)/deps/c-ares/.libs:$(PWD)/deps/libuv/.libs" EMBED=0 PYTHON=python2.7 make develop alltest cffibackendtest
