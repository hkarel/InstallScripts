#!/bin/sh

set -u

rebuild=
print_help=
install=
qtcreator_dir=/opt/qtcreator
qtcreator_ver=4.8
qbs_profile=qtc

display_help()
{
cat << EOF
Usage: ${0##*/} [hirvq]
  -h --help      display this help and exit
  -i --install   install
  -r --rebuild   full rebuild of project
  -v --qtc-vers  qtcreator version
  -q --qbs_prof  qbs profile
  Current build parameters:
    qtcreator istall .... $qtcreator_dir/$qtcreator_ver
    qtcreator version ... $qtcreator_ver
    qbs profile ......... $qbs_profile

Qbs profile print:
$(qbs config --list profiles.$qbs_profile)

EOF
}

# Обработка позиционных параметров:
#    http://wiki.bash-hackers.org/scripting/posparams
while test -n ${1:-""}
do
    case "$1" in
        -r|--rebuild)
            rebuild=yes
            shift
            ;;
        -h|--help)
            print_help=yes
            shift
            ;;
       -i|--install)
            install=yes
            shift
            ;;
        -v|--qtc-vers)
            qtcreator_ver=$2
            shift 2
            ;;
        -q|--qbs_prof)
            qbs_profile=$2
            shift 2
            ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            exit 1
            ;;
        *)  # No more options
            break
            ;;
    esac
done

if [ "$print_help" = "yes" ]; then
    display_help
    exit 0
fi

# # Определение параметров host-системы
# if [ ! -e $(dirname $0)/os_detect ]; then
#     echo "Error: os_detect script not found."
#     exit 1
# fi
# . $(dirname $0)/os_detect
# # ---

qbs_param()
{
    qbs config $1 | cut -d' ' -f2 | sed 's/\"//g'
}

strip_debug_info()
{
    if [ ! -L $1 ]; then
        res=$(file $1 | grep -E 'LSB +shared object')
        if [ -n "$res" ]; then
            echo "Stripped: $1"
            sudo strip --strip-debug --strip-unneeded $1
            return
        fi

        res=$(file $1 | grep -E 'LSB +executable')
        if [ -n "$res" ]; then
            echo "Stripped: $1"
            sudo strip --strip-all $1
        fi
    fi
}

which git > /dev/null 2>&1
if [ "$?" -ne 0 ]; then
    echo "Error: Need install the GIT"
    exit 1
fi

if [ -z "$(dpkg -l | grep -P '^ii\s+realpath')" ]; then
    echo "Need install 'realpath' utility"
    sudo apt-get install -y realpath
fi

qbs_gxx_profile=$(qbs_param profiles.$qbs_profile.baseProfile)
if [ -z $qbs_gxx_profile ]; then
    echo "Error: Qbs compiler profile not found"
    exit 1
fi

gxx_compiler=$(qbs_param profiles.$qbs_gxx_profile.cpp.toolchainInstallPath)
gxx_compiler="$gxx_compiler/g++"
if [ ! -x $gxx_compiler ]; then
    echo "Error: Compiler not found: $gxx_compiler"
    exit 1
fi

src_dir=~/Tools/qtcreator
if [ ! -d $src_dir ]; then
    echo "Error: Not found directory: $src_dir"
    exit 1
fi
cd $src_dir

if [ ! -d .git ]; then
    echo "Error: Git repository not exists"
    exit 1;
fi

QBS=$(which qbs)

set -e

if [ "$rebuild" = "yes" ]; then
    # Полная пересборка
    git clean -dfx
    git submodule foreach --recursive git clean -dfx
fi
git submodule update --init --recursive

#LLVM_INSTALL_DIR=/usr/lib/llvm-3.9
#export LLVM_INSTALL_DIR

$QBS build \
    --file qtcreator.qbs \
    --build-directory ./build \
    --command-echo-mode command-line \
    qbs.buildVariant:release \
    profile:$qbs_profile

if [ "$install" = "yes" ]; then
    sudo mkdir -p $qtcreator_dir
    cd $qtcreator_dir
    if [ -d "$qtcreator_ver" ]; then
        echo "Archiving a directory ${qtcreator_dir}/${qtcreator_ver} ..."
        sudo tar -cjf ${qtcreator_ver}_$(date +%Y.%m.%d_%H.%M.%S).tar.bz2 $qtcreator_ver
        sudo rm -rf $qtcreator_ver
    fi

    cd $src_dir
    sudo $QBS install \
        --file qtcreator.qbs \
        --build-directory ./build \
        --no-build \
        --install-root $qtcreator_dir/$qtcreator_ver

    set +e
    echo "Removing debug info ... "
    for f in $(find  $qtcreator_dir/$qtcreator_ver -type f); do
        strip_debug_info $f
    done
    set -e

    if [ "$gxx_compiler" != "$(which g++)" ]; then
        libstdc_path=$(dirname $(realpath $($gxx_compiler --print-file-name=libstdc++.so.6)))
        qtcreator_run="$qtcreator_dir/$qtcreator_ver/bin/qtcreator.sh"
        sudo sed -i.bak -e "/^LD_LIBRARY_PATH=.*/a LD_LIBRARY_PATH=${libstdc_path}:\$LD_LIBRARY_PATH" $qtcreator_run
    fi
    echo "Installation successfully completed"
fi
