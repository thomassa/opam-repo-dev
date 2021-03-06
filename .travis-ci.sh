echo pull req: $TRAVIS_PULL_REQUEST
if [ "$TRAVIS_PULL_REQUEST" != "false" ]; then
  curl -L https://github.com/$TRAVIS_REPO_SLUG/pull/$TRAVIS_PULL_REQUEST.diff -o pullreq.diff
else
  git show > pullreq.diff.tmp
  merge=`grep "^Merge: " pullreq.diff.tmp | awk -F: '{print $2}'`
  if [ "$merge" = "" ]; then
    echo Not a merge
    mv pullreq.diff.tmp pullreq.diff
  else
    echo Merge detected, extracting $merge diff
    git show $merge > pullreq.diff
  fi
fi

install_on_linux () {
  # Install OCaml and OPAM PPAs
  case "$OCAML_VERSION,$OPAM_VERSION" in
  3.12.1,1.0.0) ppa=avsm/ocaml312+opam10 ;;
  3.12.1,1.1.0) ppa=avsm/ocaml312+opam11 ;;
  4.00.1,1.0.0) ppa=avsm/ocaml40+opam10 ;;
  4.00.1,1.1.0) ppa=avsm/ocaml40+opam11 ;;
  4.01.0,1.0.0) ppa=avsm/ocaml41+opam10 ;;
  4.01.0,1.1.0) ppa=avsm/ocaml41+opam11 ;;
  4.01.0,1.1.0) ppa=avsm/ocaml41+opam12 ;;
  4.02.0,1.1.0) ppa=avsm/ocaml42+opam11 ;;
  4.02.0,1.2.0) ppa=avsm/ocaml42+opam12 ;;
  *) echo Unknown $OCAML_VERSION,$OPAM_VERSION; exit 1 ;;
  esac

  echo "yes" | sudo add-apt-repository ppa:ubuntu-virt

  echo "yes" | sudo add-apt-repository ppa:$ppa
  sudo apt-get update -qq
  sudo apt-get install -qq ocaml ocaml-native-compilers camlp4-extra opam time
}

install_on_linux

echo OCaml version
ocaml -version
echo OPAM versions
opam --version
opam --git-version

export OPAMYES=1

cd $TRAVIS_BUILD_DIR
echo Pull request:
cat pullreq.diff
# CR: this will be replaced with the OCamlot analysis of affected packages
cat pullreq.diff | sort -u | grep '^... b/packages' | sed -E 's,\+\+\+ b/packages/.*/(.*)/.*,\1,' | grep -v '^files' | grep -v '^patches' | awk -F. '{print $1}'| sort -u > tobuild.txt
echo To Build:
cat tobuild.txt

function build_one {
  pkg=$1
  echo build one: $pkg
  rm -rf ~/.opam
  opam init

  opam remote add test .
  # list all packages changed from opam 1.0 to 1.1
  case "$OPAM_VERSION" in
  1.0.0) allpkgs=`opam list -s` ;;
  *) allpkgs=`opam list -s -a` ;;
  esac
      depext=`opam install $pkg -e ubuntu`
      echo Ubuntu depexts: $depext
      if [ "$depext" != "" ]; then
        sudo apt-get install -qq pkg-config build-essential m4 $depext
      fi
      srcext=`opam install $pkg -e source,linux`
      if [ "$srcext" != "" ]; then
        curl -sL ${srcext} | bash
      fi  
    opam install ocamlfind
    sudo mkdir -p $(ocamlc -where)
    eval `opam config env`
    sudo cp $OCAML_TOPLEVEL_PATH/topfind $(ocamlc -where)

    opam install $pkg
    opam remove $pkg
    if [ "$depext" != "" ]; then
        sudo apt-get remove $depext
        sudo apt-get autoremove
    fi
}

for i in `cat tobuild.txt`; do
  build_one $i
done
