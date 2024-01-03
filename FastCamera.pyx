"""
Author: cr180
Email: cr180@cr180.com
https://github.com/SuperKsa/FastCamera
LastUpdate: 2024-01-01 00:00:00
"""
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
        bint MJPG
        object callback
        object CallBackInit
        bint stop_threads
        object cap
        bint Exit
        int ths_count
        int ExitThread
        int FPSTime
        list thread_task_map
        list thread_task_status
        int thread_task_currentID
        object Frame_Data
        double Frame_time
        int Frame_tid
        object LOCK
        bint Debug

    def __init__(self, int CameraID=0, int Width=0, int Height=0, int FPSTime=2, bint MJPG=True, int BuffSize=10, int ThreadCount=1, object Callback=None, object CallBackInit=None, bint Debug=False):
        """
        初始化参数
        :param CameraID: 相机ID 数字 自动适配linux
        :param Width: 画面 宽度
        :param Height: 画面 高度
        :param FPSTime: 帧采集间隔时间（单位：ms，建议：1-10）
        :param MJPG: 是否启用MJPG （默认：True）
        :param BuffSize: OpenCV缓存大小 默认10
        :param ThreadCount: 需要启用的线程数量(默认：1)
        :param Callback: 回调函数 新帧回调到该函数，参数：(关联线程ID, time时间戳, cv2图片对象)
        :param CallBackInit: FastCamera初始化后的回调函数 ，参数：(self)
        :param Debug: 是否输出debug日志
        """
        self.CameraID = CameraID
        self.Width = Width
        self.Height = Height
        self.FPSTime = FPSTime
        self.MJPG = MJPG
        self.buffSize = BuffSize
        if ThreadCount > 0:
            self.ths_count = ThreadCount
        else:
            self.ths_count = 1

        self.callback = Callback
        self.CallBackInit = CallBackInit  # 启动完成的回调函数
        self.Debug = Debug

        self.cap = None
        self.thread_task_map = []  # 每个线程的任务ID key=线程ID value=任务ID
        self.thread_task_status = []  # 每个线程的运行状态 key=线程ID value=状态值(0=空闲 1=忙碌)
        self.thread_task_currentID = 0  # 当前任务线程ID
        self.Frame_Data = np.zeros((Height, Width, 3), dtype=np.uint8)  # 当前帧cv2数据
        self.Frame_time = 0  # 当前帧时间戳

        self.LOCK = threading.Lock()  # 线程锁
        self.Exit = False  # 当前进程退出信号

        self._start()

        # 全局控制线程
        th_ctrl = threading.Thread(target=self._ThreadFunc_Ctrl)
        th_ctrl.daemon = True  #子线程必须和主进程一同退出，防止僵尸进程
        th_ctrl.start()

        # 启动帧回调进程
        th_call = threading.Thread(target=self._ThreadFunc__callFunc)
        th_call.daemon = True  #子线程必须和主进程一同退出，防止僵尸进程
        th_call.start()

        # 初始化完成后回调给外部
        if CallBackInit is not None:
            CallBackInit(self)

    def _start(self):

        debugString = '\n'
        debugString += ('=' * 20)
        debugString += f' FastCamera '
        debugString += ('=' * 20)

        self.ExitThread = 0  # 当前结束线程数量
        self.stop_threads = False  # 当前进程是否停止
        self.Status = 0  # 标记状态为初始

        self.thread_task_status = []
        self.thread_task_map = []

        for i in range(self.ths_count):
            self.thread_task_status.append(0)  # 标记线程状态为空闲
            self.thread_task_map.append(0)  # 标记线程任务为空
            th = threading.Thread(target=self.__ThreadFunc_reader, args=(i,))
            th.daemon = True  #子线程必须和主进程一同退出，防止僵尸进程
            th.start()
            debugString += (f'\n= Read Thread-{i} Start')

        if platform.system().lower() == 'linux':
            debugString += (f'\n= 摄像头初始化中 ID=/dev/video{self.CameraID} ThreadCount={self.ths_count}')
            self.cap = cv2.VideoCapture(f'/dev/video{self.CameraID}')
        else:
            debugString += (f'\n= 摄像头初始化中 ID={self.CameraID} ThreadCount={self.ths_count}')
            self.cap = cv2.VideoCapture(self.CameraID)
        # 检查摄像头是否成功打开
        if self.cap.isOpened():
            debugString += (f'\n= 摄像头已打开')

            if self.buffSize > 0:
                self.cap.set(cv2.CAP_PROP_BUFFERSIZE, self.buffSize)
            if self.MJPG:
                res_mjpg = self.set_mjpg()
                debugString += (f'\n= MJPG设置结果={res_mjpg}')
                res_mjpg = None

            res_size = self.set_size()
            debugString += (f'\n= 尺寸={self.Width}x{self.Height} 设置结果={res_size}')
            res_size = None

            self.startTime = time.time()
            self.Status = 2  # 标记状态为启动成功

            debugString += ('\n= 摄像头初始化完成')
        else:
            debugString += (f'\n= 摄像头打开失败 {self.CameraID}')

        if self.Debug:
            debugString += (f'\n= 线程数量={self.ths_count}')
            debugString += (f'\n= OpenCV BuffSize={self.buffSize}')
            debugString += (f'\n= FPSTime={self.FPSTime}')
            debugString += '\n'
            debugString += ('=' * 50)
            debugString += '\n'
            print(debugString)

    def _addFrame(self, taskID, tid, times, frame):
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
            except Exception as e:
                if self.Debug:
                    print(f"[FastCamera] 发生异常: {e}")

    def _ThreadFunc__callFunc(self):
        """
        帧回调函数 将帧回调给外部调用函数
        :return:
        """
        sendTime = 0.
        while True:
            if self.Exit:
                if self.Debug:
                    print(f'[FastCamera] 回调进程 退出')
                break
            if self.callback is not None:
                if sendTime < self.Frame_time:
                    try:
                        shape = self.Frame_Data.shape
                        # t = time.time()
                        self.callback(self.Frame_tid, self.Frame_time, self.Frame_Data)
                        # print(f'推送帧耗时={round((time.time() - t) * 1000)}ms')
                    except Exception as e:
                        if self.Debug:
                            print('[FastCamera] 帧回调函数报错：', e)
                        pass
                    sendTime = self.Frame_time
            time.sleep(0.001)
        self.ExitThread += 1

    def __ThreadFunc_reader(self, tid):
        """
        线程执行函数
        :param tid:
        :return:
        """
        while True:
            if self.stop_threads:
                if self.Debug:
                    print(f'[FastCamera] Thread-{tid} OutEd')
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
                        self._addFrame(taskID, tid, frame_time, frame)  # 画面添加到帧

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
                    if self.Debug:
                        print('[FastCamera] 帧读取线程报错：', e)
                    pass
                self.thread_task_status[tid] = 0  # 标记当前进程为 空闲
                self.thread_task_map[tid] = 0
                # print(f'tid={tid} 空闲')
            time.sleep(0.001)

        self.ExitThread += 1

    def _ThreadFunc_Ctrl(self):
        """
        线程函数 - 全局控制
        :return:
        """
        loopN = 0
        while True:
            if self.Exit:
                if self.Debug:
                    print('[FastCamera] 控制线程 退出')
                break

            elif self.Status == 1:
                if self.Debug:
                    print('[FastCamera] 摄像头重启中')
                self.release(False)
                while self.ExitThread != self.ths_count:
                    time.sleep(0.001)
                self._start()
                if self.Debug:
                    print('[FastCamera] 摄像头重启完成')
                self.startTime = time.time()
                self.FPS_count = 0

            try:
                if loopN >= self.FPSTime:
                    loopN = 0
                    # 查找空闲线程 并分配任务
                    for i in range(self.ths_count):
                        # 空闲线程 status=0 分配任务hash=时间戳
                        if self.thread_task_status[i] == 0:
                            self.thread_task_currentID = i

                            taskID = time.time()
                            # print(f'{self.FPSTime}ms 分配任务给 {i} = {taskID}')
                            self.thread_task_map[i] = taskID
                            break
            except Exception as e:
                if self.Debug:
                    print('[FastCamera] 任务分配主进程报错：', e)
                pass
            loopN += 1

            time.sleep(0.001)  # 1ms间隔
        self.ExitThread += 1

    def restart(self, int CameraID=-1, int Width=0, int Height=0, int FPSTime=0, bint MJPG=True, int BuffSize=-1, int ThreadCount=-1):
        """
        重启摄像头
        :return:
        """
        if CameraID > 0 and Width > 0 and Height > 0:
            self.CameraID = CameraID
            self.Width = Width
            self.Height = Height
            self.FPSTime = FPSTime
            self.MJPG = MJPG
            self.buffSize = BuffSize
            self.ths_count = ThreadCount
        self.Status = 1  # 标记为重启信号

    def set_mjpg(self):
        self.cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc('m', 'j', 'p', 'g'))
        setMJPG = self.cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc('M', 'J', 'P', 'G'))
        return setMJPG

    def set_size(self, int width=0, int height=0):
        if width > 0:
            self.Width = width
        if height > 0:
            self.Height = height

        if self.Width > 0 and self.Height > 0:
            setW = self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, self.Width)  # 设置帧宽度
            setH = self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, self.Height)  # 设置帧高度
            return setW and setH
        return False

    def set(self, int key, int value):
        self.cap.set(key, value)

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

    def read(self):
        """
        读取当前实时帧数据
        :return:
        """
        return self.Frame_time, self.Frame_Data

    def release(self, isExit=True):
        """
        关闭摄像头
        :param isExit: 是否结束整个进程
        :return:
        """
        self.stop_threads = True
        if self.cap is not None:
            self.cap.release()

        # 退出程序
        if isExit:
            self.Exit = True
            thCount = self.ths_count + 2
            while True:
                if self.ExitThread == thCount:
                    break
                time.sleep(0.001)
            # 清理数据
            self.Frame_Data = None
            self.Frame_time = 0
            self.thread_task_status = []
            self.thread_task_map = []
            if self.Debug:
                print('[FastCamera] Work End ExitEd')
        return True
