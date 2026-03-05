# pyctp
本项目使用swig将ctp的c++接口转为python接口
## 依赖
本项目依赖以下库(请根据实际情况安装)：
- python
- swig
- boost
- cmake

## 编译
### Linux及Mac编译
1. 安装依赖
* macos
```
brew install swig  boost cmake
```
* linux
```
sudo apt install swig  boost-dev cmake
```

2. 编译库

```
cd api
mkdir build
cd build
cmake ..
make
```

3. 打pip包
```
cd package
python install .

```

### Windows编译
 

## 参考
* openctp 
* vnpy_ctp
* [CTPAPI-Python开发攻略](https://zhuanlan.zhihu.com/p/688672132)。

  

