"""
Author: cr180
Email: cr180@cr180.com
https://github.com/SuperKsa/FastCamera
LastUpdate: 2024-01-01 00:00:00
"""

import threading
import time
from collections import deque

import cv2

ctypedef void (*CallbackFunc)(FastCamera)


cdef class FastCamera:
    cdef:
        float FPS
        int FPS_count
        double startTime
        double frameTimes
        double readTime
        int Status
        int CameraID
        int Width
        int Height
        int buffSize
        bint mjpg
        int queueNum
        object callback
        object TimelyScanFrame
        object Queues
        bint stop_threads
        object cap
        object th
        bint Exit
        int ths_count

    def __cinit__(self, int CameraID=0, int width=0, int height=0, bint mjpg=False, int queueNum=0, int buffSize=10, object callback=None, int thread_count=1):
        """
        初始化
        :param CameraID: 相机ID 数字 自动适配linux
        :param width: 画面 宽度
        :param height: 画面 高度
        :param mjpg: 是否启用MJPG
        :param queueNum: 最大队列数量
        :param buffSize: 缓存大小
        :param callback: 回调函数 新帧回调到该函数，参数：(time时间戳, cv2图片对象) 使用回调函数后，不应该再调用read函数，回调函数返回True表示结束进程
        :param thread_count: 线程数量 高分辨率 高FPS摄像头 建议2-5
        """

        # 打印摄像头数量
        print('=' * 40)
        print(f'= 摄像头初始化中 ID={CameraID} ThreadCount={thread_count}')
        self.TimelyScanFrame = (None, None)  # 实时帧数据 (时间戳, cv2图片对象)
        self.CameraID = CameraID
        self.Width = width
        self.Height = height
        self.mjpg = mjpg
        self.queueNum = queueNum
        self.callback = callback
        self.buffSize = buffSize
        self.cap = None


        self.start()
        self.Queues = deque(maxlen=self.queueNum)

        self.stop_threads = False  # 当前进程是否停止
        self.Status = 0
        self.ths_count = thread_count
        for i in range(self.ths_count):
            th = threading.Thread(target=self._reader)
            th.daemon = True #子线程必须和主进程一同退出，防止僵尸进程
            th.start()
            time.sleep(0.01)  # 10ms启动一个子线程

        self.Exit = 0
        while self.Exit != self.ths_count:
            time.sleep(0.1)
        # print('【VideoCapture】退出')

    def restart(self, CameraID=0, int width=0, int height=0, bint mjpg=False, int queueNum=0, buffSize=10):
        """
        重启摄像头
        :return:
        """
        self.CameraID = CameraID
        self.Width = width
        self.Height = height
        self.mjpg = mjpg
        if  self.queueNum != queueNum:
            self.queueNum = queueNum
            # 清空队列并释放内存
            self.Queues = deque(maxlen=0)
            # 重新初始化队列
            self.Queues = deque(maxlen=self.queueNum)

        print('【摄像头重启中】')
        self.Status = 2
        self.Queues.clear()  # 清空队列
        self.cap.release()
        self.start()
        print('【摄像头重启完成】')
        self.startTime = time.time()
        self.FPS_count = 0

    def start(self):
        self.cap = cv2.VideoCapture(self.CameraID)
        # 检查摄像头是否成功打开
        if self.cap.isOpened():
            print(f'= 摄像头已打开')
            self.Status = 1
            if self.buffSize > 0:
                self.cap.set(cv2.CAP_PROP_BUFFERSIZE, self.buffSize)
            if self.mjpg:
                self.set_mjpg()
            self.set_size()

            self.startTime = time.time()
            print('= 摄像头初始化完成')
        else:
            print(f'= 摄像头打开失败 {self.CameraID}')
        print('=' * 40)

    def set_mjpg(self):
        self.cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc('m', 'j', 'p', 'g'))
        setMJPG = self.cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc('M', 'J', 'P', 'G'))
        print(f'= MJPG设置结果={setMJPG}')
        return setMJPG

    def set_size(self, int width=0, int height=0):
        if width > 0:
            self.Width = width
        if height > 0:
            self.Height = height

        if self.Width > 0 and self.Height > 0:
            setW = self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, self.Width)  # 设置帧宽度
            setH = self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, self.Height)  # 设置帧高度
            print(f'= 尺寸={self.Width}x{self.Height} 设置结果={setW and setH}')

    def set(self, int key, int value):
        self.cap.set(key, value)

    # 实时读帧，将所有帧保存到队列
    def _reader(self):
        while True:
            if self.stop_threads:
                break
            try:
                if self.Status == 2:
                    time.sleep(1)
                    continue

                if not self.cap.isOpened():
                    self.Status = 0
                    time.sleep(1)
                    continue

                startFrameTime = time.time()
                # 抓取帧
                grabbed = self.cap.grab()
                # 检索帧
                if grabbed:
                    ret, frame = self.cap.retrieve()
                self.readTime = (time.time() - startFrameTime)
                if not ret:
                    self.Status = 0
                    continue

                self.Status = 3

                if self.callback:
                    try:
                        func_res = self.callback(self, startFrameTime, frame)
                        # 直接结束进程
                        if func_res == True:
                            self.release()
                            continue
                    except Exception as e:
                        pass
                else:
                    if self.queueNum > 0:
                        # if len(self.Queues) >= self.queueNum:
                        #     del self.Queues[0]
                        self.Queues.append((startFrameTime, frame))
                    else:
                        self.TimelyScanFrame = (startFrameTime, frame)

                # -------- FPS统计处理 Start -------- #
                self.FPS_count += 1
                self.FPS = round(self.FPS_count / (time.time() - self.startTime), 1)
                if self.FPS_count > 10000:
                    self.FPS_count = 1
                    self.startTime = time.time()
                # -------- FPS统计处理 End -------- #
                self.frameTimes = (time.time() - startFrameTime)

            except Exception as e:
                continue
        self.Exit += 1

    def fps(self):
        """
        当前帧率
        :return:
        """
        return round(self.FPS, 1)

    def fps_time(self):
        """
        单帧处理耗时 ms
        :return:
        """
        return round(self.frameTimes * 1000)

    def read_time(self):
        """
        帧读取时间 ms
        :return:
        """
        return round(self.readTime * 1000 / self.ths_count)

    def read(self):
        """
        读取帧
        :return:
        """
        if self.queueNum == 0:
            if self.TimelyScanFrame is not None:
                frame_time, frame = self.TimelyScanFrame
                return frame_time, frame
        else:
            if len(self.Queues):
                frame_time, frame = self.Queues[0]
                del self.Queues[0]
                return frame_time, frame
        return None, None

    def queue_count(self):
        """
        剩余队列数量
        :return:
        """
        return len(self.Queues)

    def release(self):
        """
        关闭摄像头
        :return:
        """
        self.stop_threads = True
        if len(self.Queues):
            self.Queues.clear()  # 清空队列
        self.cap.release()
        self.th.join()