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


class Demo:
    MainExit = False
    # ---------- Config ---------- #
    Config_Width = 2688  # camera Width 分辨率-宽
    Config_Height = 1520  # camera Height  分辨率-高
    Config_FPSTime = 1  # FPS
    Config_MJPG = True  # is MJPG 你应该启用MJPG
    Config_CameraID = 0  # camera ID  摄像头ID
    Config_buffSize = 10  # opencv buffer
    Config_ThreadCount = 4  # Number of thread 启用多少个子线程(>2K 60FPS 应该设置2-5)
    # ---------- Config ---------- #

    # ---------- 统计FPS 常量 ---------- #
    startTime = time.time()
    FPS_count = 0
    FPS = 0
    Frame_Data = None
    Frame_Time = 0
    Frame_Tid = 0
    # ---------- 统计FPS 常量 ---------- #

    def __init__(self):
        # 监听Ctrl+C信号
        signal.signal(signal.SIGINT, self.signal_handler)

        # 启动 FastCamera
        self.cap = FastCamera(CameraID=self.Config_CameraID, Width=self.Config_Width, Height=self.Config_Height, MJPG=self.Config_MJPG, FPSTime=self.Config_FPSTime, BuffSize=self.Config_buffSize, ThreadCount=self.Config_ThreadCount, Callback=self.callbackFrame, CallBackInit=self.callbackInit, Debug=True)

        # ---------- Detecting Main Process Exit ---------- #
        while True:
            # 监听到进程退出信号
            if self.MainExit:
                print('开始关闭进程')
                self.cap.release()
                break

            # 显示实时帧(cv2.imshow会消耗CPU资源，同时导致整个采集工作变慢！)
            if self.Frame_Data is not None:
                cv2.imshow("FastCamera Frame", self.Frame_Data)

            debugString = ''

            # 提取实时帧形状与第一个像素值
            if self.Frame_Data is not None:
                debugString = f'frame={self.Frame_Data.shape} {self.Frame_Data[0:1, 0:1, :]}'

            # 输出统计信息
            CurrentDate = datetime.fromtimestamp(time.time()).strftime("%Y-%m-%d %H:%M:%S.%f")
            sys.stdout.write(f'\r[{CurrentDate}] FPS={self.FPS}/{self.cap.fps()} FrameTime={self.cap.read_time()}ms/{self.cap.fps_time()}ms FrameKey={self.Frame_Time} 当前任务ID={self.Frame_Tid} MainExit={self.MainExit} {debugString}')
            sys.stdout.flush()

            # 监听cv2窗口键鼠信号
            waitKey = cv2.waitKey(1)
            if waitKey == 27:  # ESC 退出程序
                print('收到退出信号')
                self.MainExit = True
            elif waitKey == ord('r'):  # R键 重启摄像头 Restart
                # 方式 1：重启时传入新的参数
                # self.cap.restart(CameraID=self.Config_CameraID, Width=self.Config_Width, Height=self.Config_Height, MJPG=self.Config_MJPG, FPSTime=self.Config_FPSTime, BuffSize=self.Config_buffSize, ThreadCount=self.Config_ThreadCount)

                # 方式 2：使用初始化参数直接重启
                self.cap.restart()

            # time.sleep(0.001)
        cv2.destroyAllWindows()
        # ---------- Detecting Main Process Exit ---------- #

    def callbackInit(self, fc):
        print('FastCamera初始化完成')

    def callbackFrame(self, tid, times, frame):
        """
        This is a callback function that receives the latest frame image data.
        这是一个回调函数，接收最新的帧画面数据
        :param cap: cap Class Object (FastCamera类对象)
        :param times:  Current Frame Key (当前帧键名 time.time时间戳)
        :param frame:  Current frame (opencv img object) 当前帧opencv图片对象
        :return: If it returns True, FastCamera will terminate its operation.（如果返回True FastCamera将会结束运行）
        """

        # 这里仅作为demo例子，实际过程中，你应该在收到frame数据以后立即存入队列中，而不应该在这里进行耗时逻辑！！ #
        # This is only a demo example. In actual implementation, you should immediately store the received frame data in a queue, and avoid time-consuming logic in this context. #

        # 将帧数据传递到 self.Frame_Data
        if times > 0:
            self.Frame_Data = frame  # 当前帧
            self.Frame_Time = times  # 当前帧对应时间戳
            self.Frame_Tid = tid  # 读取当前帧的线程ID

            # 计算FPS
            self.FPS_count += 1
            self.FPS = round(self.FPS_count / (time.time() - self.startTime), 1)

    def signal_handler(self, sig, frame):
        self.MainExit = True


if __name__ == '__main__':

    # 启动线程
    P_CapRead = Process(name='DemoProcess', target=Demo)
    P_CapRead.daemon = True
    P_CapRead.start()
    P_CapRead.join()  #阻塞并等待进程结束

    print('Main Exit.')
