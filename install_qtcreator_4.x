#!/bin/bash

set -u

rebuild=
print_help=
install=
symlink_python_remove=

qtcreator_dir=/opt/qtcreator
qtcreator_ver=4.14
qbs_profile=qtc

# Определение параметров host-системы
if [ ! -e $(dirname $0)/os_detect ]; then
    echo "Error: os_detect script not found."
    exit 1
fi
. $(dirname $0)/os_detect
# ---

function display_help()
{
cat << EOF
Usage: ${0##*/}
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

function qbs_param()
{
    qbs config $1 | cut -d' ' -f2 | sed 's/\"//g'
}

function strip_debug_info()
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

if [ ! -e /usr/bin/realpath ]; then
    if [ -z "$(dpkg -l | grep -P '^ii\s+realpath')" ]; then
        echo "Need install 'realpath' utility"
        sudo apt-get install -y realpath
    fi
fi

if [ -z "$(dpkg -l | grep -P '^ii\s+libdw-dev')" ]; then
    echo "Need install 'libdw-dev' package"
    sudo apt-get install -y libdw-dev
fi

if [ "$os_id" = "ubuntu" -a "$os_ver" \> "19.04" ]; then
    if [ -z "$(dpkg -l | grep -P '^ii\s+libgl1-mesa-dev')" ]; then
        echo "Need install 'libgl1-mesa-dev' package"
        sudo apt-get install -y libgl1-mesa-dev
    fi
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

qt_lib_path=$(qbs_param profiles.$qbs_profile.moduleProviders.Qt.qmakeFilePaths)
[ -n "$qt_lib_path" ] && qt_lib_path="${qt_lib_path%%/bin*}"
#echo $qt_lib_path
#exit 0

inst_dir=$(realpath $(dirname $0))

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

if [ "$os_id" = "ubuntu" -a "$os_ver" \> "19.04" ]; then
    if [ ! -e /usr/bin/python ]; then
        symlink_python_remove=yes
        echo "Need create symlink /usr/bin/python3 -> /usr/bin/python"
        sudo ln -s /usr/bin/python3 /usr/bin/python
    fi
fi

QBS=$(which qbs)

set -e

if [ "$rebuild" = "yes" ]; then
    # Полная пересборка
    git clean -dfx
    git submodule foreach --recursive "git clean -dfx"
fi
git submodule update --init --recursive

#LLVM_INSTALL_DIR=/usr/lib/llvm-3.9
#export LLVM_INSTALL_DIR

$QBS build \
    --file qtcreator.qbs \
    --build-directory ./build \
    --command-echo-mode command-line \
    qbs.buildVariant:release \
    qbs.installPrefix:"" \
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
    
    if [ -n "$qt_lib_path" ]; then
        sudo cp $inst_dir/qtcreator-qt.conf $qtcreator_dir/$qtcreator_ver/bin/qt.conf
        sudo ln -s $qt_lib_path $qtcreator_dir/$qtcreator_ver/lib/Qt
        #sudo sed -e "s/^Prefix=.*/Prefix=${qt_lib_path}/" \
        #         -i $qtcreator_dir/$qtcreator_ver/bin/qt.conf
    fi

    qtcreator_run="$qtcreator_dir/$qtcreator_ver/bin/qtcreator.sh"

    if [ "$gxx_compiler" != "$(which g++)" ]; then
        libstdc_path=$(dirname $(realpath $($gxx_compiler --print-file-name=libstdc++.so.6)))
        sudo sed -i.bak -e "/^LD_LIBRARY_PATH=.*/a LD_LIBRARY_PATH=${libstdc_path}:\$LD_LIBRARY_PATH" $qtcreator_run
    fi

    # Принудительно включаем "Большой DPI". Оция QtCreator "Масштабировать при большом DPI"
    # не работает в Ubuntu 20.04
    # Источник: https://github.com/linuxmint/Cinnamon/issues/4902

    # Удаляем строку: exec "$bindir/qtcreator" ${1+"$@"}
    sudo sed -i.bak -r "/^exec .*\/qtcreator/d" $qtcreator_run

    sudo sh -c "echo 'export QT_SCALE_FACTOR=1'                >> $qtcreator_run"
    sudo sh -c "echo 'export QT_AUTO_SCREEN_SCALE_FACTOR=0'    >> $qtcreator_run"
    sudo sh -c "echo 'export QT_SCREEN_SCALE_FACTORS=2'        >> $qtcreator_run"
    sudo sh -c "echo 'export QTC_WELCOMEPAGE_FONT_SIZE_DOWN=1' >> $qtcreator_run"

    # Не используем QT_SCALE_FACTOR, сильно коробит интерфейс
    # sudo sh -c "#echo 'export QT_SCALE_FACTOR=1.015'  >> $qtcreator_run"

    # sudo sh -c "echo 'export QTC_MENU_FONT_SIZE=10.1' >> $qtcreator_run"

    # Добавляем строку: exec "$bindir/qtcreator" ${1+"$@"}
    sudo sh -c "echo 'exec \"\$bindir/qtcreator\" \${1+\"\$@\"}' >> $qtcreator_run"

    echo "Installation successfully completed"
fi
