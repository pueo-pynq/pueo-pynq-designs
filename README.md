# Design test firmware for the common pueo-pynq firmware

* basic_design : routes ADC channels 0-3 to buffers 0-3
* biquad8_design : routes ADC channels 0-1 through single biquad8s for testing
* lowpass_design : routes ADC channels 0-3 through the halfband filter, into buffers 0-3 and channels 0-1 to dac outputs 0-1
