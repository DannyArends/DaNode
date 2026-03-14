Build OpenSSL for Windows (or linux)
------------------------------------

##### Windows
Download the requirements:
- [Strawberry Perl](https://strawberryperl.com/)
- [NASM](https://www.nasm.us/)

Compile OpenSSL:
```
call "C:/Program Files (x86)/Microsoft Visual Studio/2019/BuildTools/VC/Auxiliary/Build/vcvars64.bat" 
cd deps/openssl
perl Configure VC-WIN64A
nmake
```

##### Linux
Install requirements:
```bash
sudo apt-get install build-essential
```
Compile OpenSSL:
```bash
cd deps/openssl
./Configure linux-x86_64
make
```