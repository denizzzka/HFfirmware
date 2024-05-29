module main;

import i2c_master;

pragma(crt_constructor)
shared static this()
{
}

extern(C) void app_main()
{
    while(1) {
        vTaskDelay(portTICK_PERIOD_MS * 10);
    }
}
