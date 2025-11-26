VERSION=$1

if [ -z "$VERSION" ]
then
      echo "No version passed. Assuming 'FP16_8x16'. Please use the script as:"
      echo "source compile_sauria.sh VERSION"
      VERSION="FP16_8x16"
fi

make clean
version=$VERSION make
