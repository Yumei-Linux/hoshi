# Installation

```sh
git clone https://github.com/Yumei-Linux/hoshi.git --depth=1
cd hoshi && zig build -Doptimize=ReleaseSafe
sudo install -Dvm755 zig-out/bin/hoshi /usr/bin
```

then update hoshi formulas database

```sh
sudo hoshi -s
```

and to reupdate it by deleting old generations

```sh
sudo hoshi -sc
```
