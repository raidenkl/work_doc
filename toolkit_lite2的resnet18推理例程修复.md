## 0.环境配置
本次测试使用的环境是猫3，ubuntu22.04，20250721的镜像。
```
#安装python工具，安装相关依赖和软件包等
sudo apt update
sudo apt-get install python3-dev python3-pip gcc
sudo apt install -y python3-opencv python3-numpy python3-setuptools

# pip命令安装rknn-toolkit-lite2
pip3 install rknn-toolkit-lite2
```
测试的时候更新了板卡的librknnrt.so，可以参考[文档](https://doc.embedfire.com/linux/rk356x/Ai/zh/latest/lubancat_ai/env/rknpu.html#rknn-api)更新。

因为用的是猫3测试，但是例程里没有rk3576的rknn模型，所以可以到[这个仓库](https://github.com/airockchip/rknn-toolkit2/tree/master/rknn-toolkit-lite2/examples/resnet18)获取，把`resnet18_for_rk3576.rknn`放到`dev_env/rknn_toolkit_lite2/examples/inference_with_lite/`这个路径下就可以了。

## 1.例程修改
因为修改的地方有点多，这里直接发出可以用的例程如下：
>test.py
```python
import cv2
import numpy as np
import platform
from rknnlite.api import RKNNLite

# decice tree for rk356x/rk3588
DEVICE_COMPATIBLE_NODE = '/proc/device-tree/compatible'

def get_host():
    # get platform and device type
    system = platform.system()
    machine = platform.machine()
    os_machine = system + '-' + machine
    if os_machine == 'Linux-aarch64':
        try:
            with open(DEVICE_COMPATIBLE_NODE) as f:
                device_compatible_str = f.read()
                if 'rk3588' in device_compatible_str:
                    host = 'RK3588'
                elif 'rk3562' in device_compatible_str:
                    host = 'RK3562'
                elif 'rk3576' in device_compatible_str:
                    host = 'RK3576'
                else:
                    host = 'RK3566_RK3568'
        except IOError:
            print('Read device node {} failed.'.format(DEVICE_COMPATIBLE_NODE))
            exit(-1)
    else:
        host = os_machine
    return host

INPUT_SIZE = 224

RK3566_RK3568_RKNN_MODEL = 'resnet18_for_rk3566_rk3568.rknn'
RK3588_RKNN_MODEL = 'resnet18_for_rk3588.rknn'
RK3562_RKNN_MODEL = 'resnet18_for_rk3562.rknn'
RK3576_RKNN_MODEL = 'resnet18_for_rk3576.rknn'


def show_top5(result):
    output = result[0].reshape(-1)
    # softmax
    output = np.exp(output)/sum(np.exp(output))
    output_sorted = sorted(output, reverse=True)
    top5_str = 'resnet18\n-----TOP 5-----\n'
    for i in range(5):
        value = output_sorted[i]
        index = np.where(output == value)
        for j in range(len(index)):
            if (i + j) >= 5:
                break
            if value > 0:
                topi = '{}: {}\n'.format(index[j], value)
            else:
                topi = '-1: 0.0\n'
            top5_str += topi
    print(top5_str)


if __name__ == '__main__':

    host_name = get_host()
    if host_name == 'RK3566_RK3568':
        rknn_model = RK3566_RK3568_RKNN_MODEL
    elif host_name == 'RK3562':
        rknn_model = RK3562_RKNN_MODEL
    elif host_name == 'RK3588':
        rknn_model = RK3588_RKNN_MODEL
    elif host_name == 'RK3576':
        rknn_model = RK3576_RKNN_MODEL

    else:
        print("This demo cannot run on the current platform: {}".format(host_name))
        exit(-1)

    rknn_lite = RKNNLite()

    # load RKNN model
    print('--> Load RKNN model')
    ret = rknn_lite.load_rknn(rknn_model)
    if ret != 0:
        print('Load RKNN model failed')
        exit(ret)
    print('done')

    ori_img = cv2.imread('./space_shuttle_224.jpg')
    img = cv2.cvtColor(ori_img, cv2.COLOR_BGR2RGB)
    #新增下面这行解决The input[0] need 4dims input, but 3dims input buffer feed的问题
    img = np.expand_dims(img, 0)
    # init runtime environment
    print('--> Init runtime environment')
    # run on RK356x/RK3588 with Debian OS, do not need specify target.
    if host_name == 'RK3588':
        ret = rknn_lite.init_runtime(core_mask=RKNNLite.NPU_CORE_0)
    else:
        ret = rknn_lite.init_runtime()
    if ret != 0:
        print('Init runtime environment failed')
        exit(ret)
    print('done')

    # Inference
    print('--> Running model')
    outputs = rknn_lite.inference(inputs=[img])
    show_top5(outputs)
    print('done')

    rknn_lite.release()

```