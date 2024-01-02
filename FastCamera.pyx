"""
Author: cr180
Email: cr180@cr180.com
https://github.com/SuperKsa/FastCamera
LastUpdate: 2024-01-01 00:00:00
"""
import math
import platform
import threading
import time
import traceback

import cv2
import numpy as np



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
        object callback
        bint stop_threads
        object cap
        bint Exit
        int ths_count
        int ExitThread
        int readFPS
        int read_step_time
        list thread_task_map
        list thread_task_status
        int thread_task_currentID
        object Frame_Data
        double Frame_time
        int Frame_tid
        object LOCK

    def __cinit__(self, int CameraID=0, int width=0, int height=0, bint mjpg=False, int queueNum=0, int buffSize=10, int thread_count=1, object callback=None):
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

        self.CameraID = CameraID
        self.Width = width
        self.Height = height
        self.mjpg = mjpg
        self.callback = callback
        self.buffSize = buffSize
        self.ths_count = thread_count
        self.cap = None

        self.readFPS = 60  # 采集帧率
        self.read_step_time = math.floor(1000 / self.readFPS) - 10  # 每帧间隔时间
        self.thread_task_map = []
        self.thread_task_status = []
        self.thread_task_currentID = 0  # 当前任务线程ID
        self.Frame_Data = np.zeros((height, width, 3), dtype=np.uint8)
        self.Frame_time = 0

        self.LOCK = threading.Lock()



        # 启动帧回调进程
        th = threading.Thread(target=self._callFunc)
        th.daemon = True  #子线程必须和主进程一同退出，防止僵尸进程
        th.start()

        self.start()


        self.Exit = False

        loopN = 0
        while True:
            self.read_step_time = math.floor(1000 / self.readFPS) - 10
            if self.Exit:
                while True:
                    if self.ExitThread == self.ths_count:
                        return
                    time.sleep(0.001)

            elif self.Status == 1:
                print('【摄像头重启中】')
                self.release(False)
                while self.ExitThread != self.ths_count:
                    time.sleep(0.001)
                self.start()
                print('【摄像头重启完成】')
                self.startTime = time.time()
                self.FPS_count = 0

            try:
                if loopN >= self.read_step_time:
                    loopN = 0
                    # 查找空闲线程 并分配任务
                    for i in range(self.ths_count):
                        # 空闲线程 status=0 分配任务hash=时间戳
                        if self.thread_task_status[i] == 0:
                            self.thread_task_currentID = i
                            # print(f'分配任务给 {i}')
                            taskID = time.time()
                            self.thread_task_map[i] = taskID
                            break
            except Exception as e:
                print('任务分配主进程报错：', e)
                pass
            loopN += 1

            time.sleep(0.001)  # 1ms间隔

        print('【VideoCapture】进程退出')
        # sys.exit()

    def restart(self, CameraID=0, width=0, height=0, mjpg=False, queueNum=0, buffSize=10):
        """
        重启摄像头
        :return:
        """
        self.CameraID = CameraID
        self.Width = width
        self.Height = height
        self.mjpg = mjpg


        self.Status = 1


    def start(self):
        self.ExitThread = 0  # 当前结束线程数量
        self.stop_threads = False  # 当前进程是否停止
        self.Status = 0

        self.thread_task_status = []
        self.thread_task_map = []
        for i in range(self.ths_count):
            self.thread_task_status.append(0)  # 标记线程状态为空闲
            self.thread_task_map.append(0)  # 标记线程任务为空

            th = threading.Thread(target=self._reader, args=(i,))
            th.daemon = True  #子线程必须和主进程一同退出，防止僵尸进程
            th.start()


        if platform.system().lower() == 'linux':
            print('=' * 40)
            print(f'= 摄像头初始化中 ID=/dev/video{self.CameraID} ThreadCount={self.ths_count}')
            self.cap = cv2.VideoCapture(f'/dev/video{self.CameraID}')
        else:
            print('=' * 40)
            print(f'= 摄像头初始化中 ID={self.CameraID} ThreadCount={self.ths_count}')
            self.cap = cv2.VideoCapture(self.CameraID)
        # 检查摄像头是否成功打开
        if self.cap.isOpened():
            print(f'= 摄像头已打开')

            if self.buffSize > 0:
                self.cap.set(cv2.CAP_PROP_BUFFERSIZE, self.buffSize)
            if self.mjpg:
                self.set_mjpg()
            self.set_size()

            self.startTime = time.time()
            self.Status = 2

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

    def addFrame(self, taskID, tid, times, frame):
        with self.LOCK:
            # t = time.time()
            try:
                shape = frame.shape  # 尝试访问图像的形状 防止报错
                # if times > self.Frame_time and not np.array_equal(frame, self.Frame_Data):
                if times > self.Frame_time:
                    self.Frame_Data = frame
                    self.Frame_time = times
                    self.Frame_tid = tid
                    # print(f'更新帧耗时={round((time.time() - t) * 1000)}ms')
            except AttributeError as e:
                print(f"图像不完整1: {e}")
            except IOError as e:
                print(f"发生IOError2: {e}")
            except Exception as e:
                print(f"发生了其他异常: {e}")

    def _callFunc(self):
        """
        帧回调函数 将帧回调给外部调用函数
        :return:
        """
        sendTime = 0.
        while True:
            if self.stop_threads:
                print(f'【FastCamera】 回调进程退出 OutEd')
                break
            if sendTime < self.Frame_time:
                try:
                    shape = self.Frame_Data.shape
                    # t = time.time()
                    self.callback(self, self.Frame_tid, self.Frame_time, self.Frame_Data)
                    # print(f'推送帧耗时={round((time.time() - t) * 1000)}ms')
                except AttributeError as e:
                    print(f"图像不完整: {e}")
                except IOError as e:
                    print(f"发生IOError: {e}")
                except Exception as e:
                    print('帧回调函数报错：', e)
                    pass
                sendTime = self.Frame_time
            time.sleep(0.001)


    # 实时读帧，将所有帧保存到队列
    def _reader(self, tid):
        print(f'【FastCamera】 Thread-{tid} 启动')
        while True:
            if self.stop_threads:
                print(f'【FastCamera】 Thread-{tid} OutEd')
                break
            # 如果当前存在任务
            taskID = self.thread_task_map[tid]
            if taskID > 0 and self.Status >= 2 and self.cap is not None and self.cap.isOpened():
                self.thread_task_status[tid] = 1  # 标记当前进程为忙碌
                try:
                    startFrameTime = time.time()
                    frame_time = 0
                    ret, frame = self.cap.read()
                    self.readTime = (time.time() - startFrameTime)
                    # 读取到画面
                    if ret:
                        self.Status = 3
                        frame_time = startFrameTime
                        self.addFrame(taskID, tid, frame_time, frame)  # 画面添加到帧

                        # -------- FPS统计处理 Start -------- #
                        time_x = (time.time() - self.startTime)
                        self.FPS_count += 1
                        if time_x > 0:
                            self.FPS = round(self.FPS_count / time_x, 1)
                        else:
                            self.FPS = 0
                        if self.FPS_count > 10000:
                            self.FPS_count = 1
                            self.startTime = time.time()
                        # -------- FPS统计处理 End -------- #
                    self.frameTimes = (time.time() - startFrameTime)

                except Exception as e:
                    traceback.print_exc()
                    print('帧读取线程报错：', e)
                    pass
                self.thread_task_status[tid] = 0  # 标记当前进程为 空闲
                self.thread_task_map[tid] = 0
                # print(f'tid={tid} 空闲')
            time.sleep(0.001)

        self.ExitThread += 1


    def fps(self) -> float:
        """
        当前帧率
        :return:
        """
        return round(self.FPS, 1)

    def fps_time(self) -> int:
        """
        单帧处理耗时 ms
        :return:
        """
        return round(self.frameTimes * 1000)

    def read_time(self) -> int:
        """
        帧读取时间 ms
        :return:
        """
        if self.readTime > 0:
            return round(self.readTime * 1000 / self.ths_count)
        return 0

    def release(self, isExit=True):
        """
        关闭摄像头
        :return:
        """
        self.stop_threads = True
        if self.cap is not None:
            self.cap.release()
        if isExit:
            self.Exit = True
        return True
