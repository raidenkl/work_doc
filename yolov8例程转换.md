## 0.前置准备
参考[ai文档](https://doc.embedfire.com/linux/rk356x/Ai/zh/latest/lubancat_ai/env/env.html)配置好环境，需要有conda和rknntoolkit2。
以下操作，全部在x86_64的电脑下执行，不在板卡执行。
## 1.创建相关环境
参考的是[这个文档](https://doc.embedfire.com/linux/rk356x/Ai/zh/latest/lubancat_ai/example/yolov8.html)。

```
# 使用conda创建虚拟环境
conda create -n yolov8 python=3.9
conda activate yolov8

# 通过拉取仓库然后安装
git clone https://github.com/ultralytics/ultralytics
cd ultralytics
pip install -e .

# 安装成功后，使用命令yolo简单看下版本
yolo version

# 创建一个目录，然后获取官方仓库的权重
mkdir yolov8
cd yolov8
wget https://github.com/ultralytics/assets/releases/download/v0.0.0/yolov8n.pt

```

## 2.转换模型

### 2.1 转换torchscript模型

测试 airockchip/ultralytics_yolov8 模型导出，注意教程测试的是rk_opt_v1分支， 该分支将导出torchscript模型，如果使用main分支默认导出onnx模型，模型转换成rknn时注意修改下加载模型函数。
```
# 拉取airockchip/ultralytics_yolov8，rk_opt_v1分支
git clone -b rk_opt_v1  https://github.com/airockchip/ultralytics_yolov8.git
cd ultralytics_yolov8

# 复制训练的模型yolov8n.pt到ultralytics_yolov8目录下
# 然后修改./ultralytics/cfg/default.yaml文件，主要是设置下model，为自己训练的模型路径：
    model: ./yolov8n.pt # (str, optional) path to model file, i.e. yolov8n.pt, yolov8n.yaml
    data:  # (str, optional) path to data file, i.e. coco128.yaml
    epochs: 100  # (int) number of epochs to train for

# 导出模型
(yolov8) llh@anhao:~/ultralytics_yolov8$ export PYTHONPATH=./
(yolov8) llh@anhao:~/ultralytics_yolov8$ python ./ultralytics/engine/exporter.py
```
如果执行上面报错内容如下：
```
Traceback (most recent call last):
  File "/home/dev/ai/yolov8/ultralytics_yolov8/./ultralytics/engine/exporter.py", line 1020, in <module>
    export()
  File "/home/dev/ai/yolov8/ultralytics_yolov8/./ultralytics/engine/exporter.py", line 1011, in export
    model = YOLO(cfg.model)
  File "/home/dev/ai/yolov8/ultralytics_yolov8/ultralytics/engine/model.py", line 94, in __init__
    self._load(model, task)
  File "/home/dev/ai/yolov8/ultralytics_yolov8/ultralytics/engine/model.py", line 140, in _load
    self.model, self.ckpt = attempt_load_one_weight(weights)
  File "/home/dev/ai/yolov8/ultralytics_yolov8/ultralytics/nn/tasks.py", line 624, in attempt_load_one_weight
    ckpt, weight = torch_safe_load(weight)  # load ckpt
  File "/home/dev/ai/yolov8/ultralytics_yolov8/ultralytics/nn/tasks.py", line 563, in torch_safe_load
    return torch.load(file, map_location='cpu'), file  # load
  File "/home/dev/anaconda3/envs/yolov8/lib/python3.9/site-packages/torch/serialization.py", line 1529, in load
    raise pickle.UnpicklingError(_get_wo_message(str(e))) from None
_pickle.UnpicklingError: Weights only load failed. This file can still be loaded, to do so you have two options, do those steps only if you trust the source of the checkpoint. 
        (1) In PyTorch 2.6, we changed the default value of the `weights_only` argument in `torch.load` from `False` to `True`. Re-running `torch.load` with `weights_only` set to `False` will likely succeed, but it can result in arbitrary code execution. Do it only if you got the file from a trusted source.
        (2) Alternatively, to load with `weights_only=True` please check the recommended steps in the following error message.
        WeightsUnpickler error: Unsupported global: GLOBAL ultralytics.nn.tasks.DetectionModel was not an allowed global by default. Please use `torch.serialization.add_safe_globals([ultralytics.nn.tasks.DetectionModel])` or the `torch.serialization.safe_globals([ultralytics.nn.tasks.DetectionModel])` context manager to allowlist this global if you trust this class/function.

Check the documentation of torch.load to learn more about types accepted by default with weights_only https://pytorch.org/docs/stable/generated/torch.load.html.
```
可以执行一下
```
export TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD=1
```
再执行导出模型的命令。

成功之后导出的是torchscript格式，还要转成rknn。

### 2.2 转换rknn模型
需要把conda从yolo8切成rknntoolkit2
```
# 列出创建的虚拟环境
conda info --envs

# 激活环境，我这边是toolkit2_1.6
conda activate toolkit2_1.6

(toolkit2_1.6) dev@localhost
```

这时候用我们网盘的ai例程的脚本转换，例程的获取请去我们的网盘下载，那个压缩包就是。路径是: 
> 1-野火开源图书_教程文档\配套代码\嵌入式AI应用开发实战指南

```
# 进入到例程转换的目录，我直接解压到~目录了
cd ~/lubancat_ai_manual_code/example/yolov8/yolov8_det
# 把2.1生成的torchscript模型复制到yolov8_det/model文件夹里面，再执行下一步模型转换
# 模型转换
python pt2rknn.py ./model/yolov8n_rknnopt.torchscript rk3588

```

等待转换完成，model目录就有rknn文件了。


## 3.板卡端部署

首先需要安装编译例程需要的cmake和opencv：
```
sudo apt install cmake
sudo apt install libopencv-dev
```
当然也可以用对应的源码编译安装，但是太麻烦了就不多叙述了。

后面直接参考鲁班猫的ai文档编译例程使用就可以。