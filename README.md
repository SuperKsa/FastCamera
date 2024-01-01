# FastCamera

FastCamera在OpenCV之上运行，能够处理CPU上的4K 120FPS摄像头采集。如果硬件资源足够，甚至可以实现8K 120FPS。

FastCamera runs on top of OpenCV and is capable of handling the capture of 4K 120FPS cameras on CPU. If hardware resources are sufficient, it can even achieve 8K120FPS.

---

#### Python版本
Python >= 3.7

---

#### 必须的组件：
`pip install opencv-python numpy setuptools Cython`

---
#### 如何使用？(How to use?)

请参考`demo.py`中的代码！

(Please refer to the code in `demo.py`!)

或者重新编译它：

(Alternatively, recompile it by:)
```
git clone https://github.com/SuperKsa/FastCamera.git
cd FastCamera
python setup.py build_ext --inplace
```

主要代码来自文件：`FastCamera.pyx`
(The main code is in the file: `FastCamera.pyx`.)
---

忠告(Advice)：

你应该在一个独立的子进程中使用，因为读取摄像头画面并解码、传输会消耗CPU资源，所以在整个读取摄像头画面的流程中都不应该存在额外耗时操作。当你通过回调函数接收到帧数据时，应该立即将其放入待处理队列中！

You should use it in a separate subprocess because reading camera frames, decoding, and transmitting consume CPU resources. Therefore, there should be no additional time-consuming operations throughout the entire process of reading camera frames. When you receive frame data through the callback function, you should immediately put it into the processing queue!

---

#### 为什么需要Cython？（Why do we need Cython?）
因为我们需要尽可能的减少Python低性能产生的影响，尽可能简单的利用C语言压榨CPU的性能

Because we aim to minimize the impact of Python's low performance and efficiently leverage the CPU's capabilities by making use of C language as much as possible.

---
#### 也许它能在树莓派4B/RK3566也会有非常好的表现！
#### Perhaps it could also deliver excellent performance on Raspberry Pi 4B/ Orangepi-4(RK3566).

---
你可以自由的使用它，包括商业项目中，但必须保留我的版权信息！

You are free to use it, including in commercial projects, but you must retain my copyright information.

---

如果你愿意修改代码，让它工作得更好，请你clone，非常感谢！

If you are willing to improve the code, please feel free to clone it. Your contributions are greatly appreciated!

---
```
Author: cr180
Email: cr180@cr180.com
https://github.com/SuperKsa/FastCamera
LastUpdate: 2024-01-01 00:00:00
```