# Console server
Console server exports QEMU serial console to multiple clients. On start,
QEMU connects to the console server. The server allows multiple clients to
attach the same console, although it is still one console per QEMU.
