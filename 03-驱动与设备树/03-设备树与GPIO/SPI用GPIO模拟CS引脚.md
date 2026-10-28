## 0.源设备树插件
> rk3588-lubancat-spi0-m1-overlay.dts
```
/dts-v1/;
/plugin/;

#include <dt-bindings/gpio/gpio.h>
#include <dt-bindings/pinctrl/rockchip.h>

/ {
	fragment@0 {
		target = <&spi0>;

		__overlay__ {
			status = "okay";
			#address-cells = <1>;
			#size-cells = <0>;
			pinctrl-names = "default";
			pinctrl-0 = <&spi0m1_cs0 &spi0m1_pins>;
			num-cs = <1>;

			spi_dev@0 {
				compatible = "rockchip,spidev";
				reg = <0>; //chip select 0:cs0  1:cs1
				spi-max-frequency = <24000000>; //spi output clock
			};
		};
	};
};

```
以上面的设备树为蓝本修改的。
## 1.修改方法
首先是要修改pinctrl引用的节点，因为cs脚用gpio模拟，就不复用cs0引脚了，可以去掉。

再就是添加对应的gpio来模拟cs引脚，添加的方法是自定义`cs-gpios =`。

要修改`num-cs`的数值，因为它决定spi片选数量。

最后要再添加一个spidev节点。

## 2.修改后的设备树插件
> rk3588-lubancat-spi0-m1-gpio-2cs-overlay.dts
```
/dts-v1/;
/plugin/;

#include <dt-bindings/gpio/gpio.h>
#include <dt-bindings/pinctrl/rockchip.h>

/ {
	fragment@0 {
		target = <&spi0>;

		__overlay__ {
			status = "okay";
			#address-cells = <1>;
			#size-cells = <0>;
			pinctrl-names = "default";
			pinctrl-0 = <&spi0m1_pins>;
			cs-gpios =  <&gpio4 RK_PB2 GPIO_ACTIVE_LOW>,
						<&gpio4 RK_PB3 GPIO_ACTIVE_LOW>;
			num-cs = <2>;

			spi_dev@0 {
				compatible = "rockchip,spidev";
				reg = <0>; //chip select 0:cs0  1:cs1
				spi-max-frequency = <24000000>; //spi output clock
			};

			spi_dev@1 {
				compatible = "rockchip,spidev";
				reg = <1>; //chip select 0:cs0  1:cs1
				spi-max-frequency = <24000000>; //spi output clock
			};
		};
	};
};

```