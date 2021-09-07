#!/bin/bash
set -e -x

update_version_metadata() {
  current_time=$(python -c "from time import time; from os import environ; print(int(environ.get('SOURCE_DATE_EPOCH', time())))")
  date=$(python -c "from datetime import datetime; print(datetime.utcfromtimestamp($current_time).strftime('%Y%m%d'))")
  echo "Version date is: $date"
  git_tag=$(git rev-parse HEAD)
  echo "Git tag is: $git_tag"

  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/_kivy_git_hash = ''/_kivy_git_hash = '$git_tag'/" kivy/_version.py
    sed -i '' "s/_kivy_build_date = ''/_kivy_build_date = '$date'/" kivy/_version.py
  else
    sed -i "s/_kivy_git_hash = ''/_kivy_git_hash = '$git_tag'/" kivy/_version.py
    sed -i "s/_kivy_build_date = ''/_kivy_build_date = '$date'/" kivy/_version.py
  fi
}

generate_sdist() {
  python3 -m pip install cython
  python3 setup.py sdist --formats=gztar
  python3 -m pip uninstall cython -y
}

install_kivy_test_run_apt_deps() {
  sudo apt-get update
  python --version
  sudo apt-get -y install libsdl2-dev libsdl2-ttf-dev libsdl2-image-dev libsdl2-mixer-dev
  sudo apt-get -y install libgstreamer1.0-dev gstreamer1.0-alsa gstreamer1.0-plugins-base
  sudo apt-get -y install libsmpeg-dev libswscale-dev libavformat-dev libavcodec-dev libjpeg-dev libtiff5-dev libx11-dev libmtdev-dev
  sudo apt-get -y install build-essential libgl1-mesa-dev libgles2-mesa-dev
  sudo apt-get -y install xvfb pulseaudio xsel
}

install_python() {
  sudo apt-get -y install python3 python3-dev python3-setuptools
}

install_kivy_test_run_pip_deps() {
  curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
  python3 get-pip.py --user
  python --version
  python3 -m pip install --upgrade pip setuptools wheel
  CYTHON_INSTALL=$(
    KIVY_NO_CONSOLELOG=1 python3 -c \
      "from kivy.tools.packaging.cython_cfg import get_cython_versions; print(get_cython_versions()[0])" \
      --config "kivy:log_level:error"
  )
  python3 -m pip install -I "$CYTHON_INSTALL" coveralls
  if [ $(python3 -c 'import sys; print("{}{}".format(*sys.version_info))') -le "35" ]; then
    python3 -m pip install twine~=1.15.0
  else
    python3 -m pip install twine
  fi
}

install_kivy_test_wheel_run_pip_deps() {
  python3 -m pip install --upgrade pip setuptools wheel
}

prepare_env_for_unittest() {
  python --version
  /sbin/start-stop-daemon --start --quiet --pidfile /tmp/custom_xvfb_99.pid --make-pidfile --background \
    --exec /usr/bin/Xvfb -- :99 -screen 0 1280x720x24 -ac +extension GLX
}

install_kivy() {
  python3 -m pip install -e "$(pwd)[dev,full]"
}


create_kivy_examples_wheel() {
  KIVY_BUILD_EXAMPLES=1 python3 -m pip wheel . -w dist/
}

install_kivy_examples_wheel() {
  root="$(pwd)"
  cd ~
  python3 -m pip install --pre --no-index --no-deps -f "$root/dist" "kivy_examples"
  python3 -m pip install --pre -f "$root/dist" "kivy_examples[full,dev]"
}

install_kivy_wheel() {
  python --version
  sudo apt-get -y install ${{ matrix.python }}-dev
  sudo apt-get -y install git libavdevice-dev
 # git clone https://github.com/matham/ffpyplayer
 # cd ffpyplayer/
 # python setup.py install
  #cd ..
  
  root="$(pwd)"
  cd ~

  version=$(python3 -c "import sys; print('{}{}'.format(sys.version_info.major, sys.version_info.minor))")
  if [ `uname -m` == "aarch64" ]; then
    kivy_fname=$(ls "$root"/dist/Kivy-*$version*aarch64*.whl | awk '{ print length, $0 }' | sort -n -s | cut -d" " -f2- | head -n1)
  else
    kivy_fname=$(ls "$root"/dist/Kivy-*$version*x86_64*.whl | awk '{ print length, $0 }' | sort -n -s | cut -d" " -f2- | head -n1)
  fi
  python3 -m pip install "${kivy_fname}[full,dev]"
}

install_kivy_sdist() {
  root="$(pwd)"
  cd ~

  kivy_fname=$(ls $root/dist/Kivy-*.tar.gz)
  python3 -m pip install "$kivy_fname[full,dev]"
}

test_kivy() {
  rm -rf kivy/tests/build || true
  KIVY_NO_ARGS=1 python3 -m pytest --maxfail=10 --timeout=300 --cov=kivy --cov-report term --cov-branch "$(pwd)/kivy/tests"
}

test_kivy_benchmark() {
  KIVY_NO_ARGS=1 python3 -m pytest "$(pwd)/kivy/tests" --benchmark-only
}

test_kivy_install() {
  python --version
  cd ~
  python3 -c 'import kivy'
  test_path=$(KIVY_NO_CONSOLELOG=1 python3 -c 'import kivy.tests as tests; print(tests.__path__[0])' --config "kivy:log_level:error")
  cd "$test_path"

  cat >.coveragerc <<'EOF'
[run]
  plugins = kivy.tools.coverage

EOF
  KIVY_TEST_AUDIO=0 KIVY_NO_ARGS=1 python3 -m pytest . --maxfail=10 --timeout=300
}

upload_coveralls() {
  python3 -m coveralls
}

validate_pep8() {
  python3 -m pip install flake8
  make style
}

generate_docs() {
  make html
}

upload_docs_to_server() {
  branch="docs-$1"
  commit="$2"

  # only upload docs if we have a branch for it
  if [ -z "$(git ls-remote --heads https://github.com/kivy/kivy-website-docs.git "$branch")" ]; then
    return
  fi

  git clone --depth 1 --branch "$branch" https://github.com/kivy/kivy-website-docs.git
  cd kivy-website-docs

  git config user.email "kivy@kivy.org"
  git config user.name "Kivy bot"
  git remote rm origin || true
  git remote add origin "https://x-access-token:${DOC_PUSH_TOKEN}@github.com/kivy/kivy-website-docs.git"

  rsync --delete --force --exclude .git/ --exclude .gitignore -r ../doc/build/html/ .

  git add .
  git add -u
  if ! git diff --cached --exit-code --quiet; then
    git commit -m "Docs for git-$commit"
    git push origin "$branch"
  fi
}

generate_manylinux2010_wheels() {
  image=$1

  python3 -m pip install twine

  mkdir dist
  chmod +x .ci/build-wheels-linux.sh
  docker run --rm -v "$(pwd):/io" "$image" "/io/.ci/build-wheels-linux.sh"
  sudo rm dist/*-linux*
}

generate_armv7l_wheels() {
  image=$1

  mkdir dist
  docker build -f .ci/Dockerfile.armv7l -t kivy/kivy-armv7l --build-arg image="$image" --build-arg KIVY_CROSS_PLATFORM="$2" --build-arg KIVY_CROSS_SYSROOT="$3" .
  docker cp "$(docker create kivy/kivy-armv7l)":/kivy-wheel .
  cp kivy-wheel/Kivy-* dist/

  # Create a copy with the armv6l suffix
  for name in dist/*.whl; do
    new_name="${name/armv7l/armv6l}"
    cp -n "$name" "$new_name"
  done
}

rename_wheels() {
  wheel_date=$(python3 -c "from datetime import datetime; print(datetime.utcnow().strftime('%Y%m%d'))")
  echo "wheel_date=$wheel_date"
  git_tag=$(git rev-parse --short HEAD)
  echo "git_tag=$git_tag"
  tag_name=$(KIVY_NO_CONSOLELOG=1 python3 \
    -c "import kivy; _, tag, n = kivy.parse_kivy_version(kivy.__version__); print(tag + n) if n is not None else print(tag or 'something')" \
    --config "kivy:log_level:error")
  echo "tag_name=$tag_name"
  wheel_name="$tag_name.$wheel_date.$git_tag-"
  echo "wheel_name=$wheel_name"

  ls dist/
  for name in dist/*.whl; do
    new_name="${name/$tag_name-/$wheel_name}"
    if [ ! -f "$new_name" ]; then
      cp -n "$name" "$new_name"
    fi
  done
  ls dist/
}

upload_file_to_server() {
  ip="$1"
  server_path="$2"
  file_pat=${3:-*.whl}
  file_path=${4:-dist}

  if [ ! -d ~/.ssh ]; then
    mkdir ~/.ssh
  fi

  printf "%s" "$UBUNTU_UPLOAD_KEY" >~/.ssh/id_ed25519
  chmod 600 ~/.ssh/id_ed25519

  echo -e "Host $ip\n\tStrictHostKeyChecking no\n" >>~/.ssh/config
  rsync -avh -e "ssh -p 2458" --include="*/" --include="$file_pat" --exclude="*" "$file_path/" "root@$ip:/web/downloads/ci/$server_path"
}

upload_artifacts_to_pypi() {
  python3 -m pip install twine
  twine upload dist/*
}
