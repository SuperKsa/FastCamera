"""
Author: cr180
Email: cr180@cr180.com
https://github.com/SuperKsa/FastCamera
LastUpdate: 2024-01-01 00:00:00
"""

import signal
import sys
import time
from datetime import datetime
from multiprocessing import Process

import cv2

from FastCamera import FastCamera

MainExit = False

# ---------- 监听主进程退出 ---------- #
def signal_handler(sig, frame):
    global MainExit
    MainExit = True
    print('Detecting Ctrl+C to exit the main process')
signal.signal(signal.SIGINT, signal_handler)
# ---------- 监听主进程退出 ---------- #


# ---------- Config ---------- #
Width = 1920  # camera Width 分辨率-宽
Height = 1080  # camera Height  分辨率-高
MJPG = True  # is MJPG 你应该启用MJPG
CameraID = 0  # camera ID  摄像头ID
buffSize = 0  # opencv buffer
CapThreadCount = 2  # Number of thread 启用多少个子线程(>2K 60FPS 应该设置2-5)
QueueNum = 0  # read Queue num  （帧队列 待启用的参数）
# ---------- Config ---------- #

def callbackFrame(cap:FastCamera, times, frame):
    """
    This is a callback function that receives the latest frame image data.
    这是一个回调函数，接收最新的帧画面数据
    :param cap: cap Class Object (FastCamera类对象)
    :param times:  Current Frame Key (当前帧键名 time.time时间戳)
    :param frame:  Current frame (opencv img object) 当前帧opencv图片对象
    :return: If it returns True, FastCamera will terminate its operation.（如果返回True FastCamera将会结束运行）
    """

    # ---------- Detecting Main Process Exit ---------- #
    global MainExit
    if MainExit:
        cap.release()  # exit FastCamera class  (主动结束)
        return True  # or return True exit （可选择的）
    # ---------- Detecting Main Process Exit ---------- #


    # 这里仅作为demo例子，实际过程中，你应该在收到frame数据以后立即存入队列中，而不应该在这里进行耗时逻辑！！ #
    # This is only a demo example. In actual implementation, you should immediately store the received frame data in a queue, and avoid time-consuming logic in this context. #

    cv2.imshow("FastCamera Frame",frame)


    CurrentDate = datetime.fromtimestamp(time.time()).strftime("%Y-%m-%d %H:%M:%S.%f")
    sys.stdout.write(f'\r[{CurrentDate}] FPS={cap.fps()} FrameTime={cap.read_time()}ms/{cap.fps_time()}ms FrameKey={times} MainExit={MainExit}')
    sys.stdout.flush()

    waitKey = cv2.waitKey(1)
    if waitKey == 27:
        cap.release()
    elif waitKey == ord('q'):  # Exit
        cap.release()

    elif waitKey == ord('r'):  # Restart
        cap.restart(CameraID=CameraID, width=Width, height=Height, mjpg=MJPG, queueNum=QueueNum, buffSize=buffSize)



if __name__ == '__main__':
    P_CapRead = Process(name='FastCamera', target=FastCamera, args=(CameraID, Width, Height, MJPG, QueueNum, buffSize, callbackFrame, CapThreadCount, ))
    P_CapRead.daemon = True
    P_CapRead.start()
    P_CapRead.join()
    print('Main Exit.')