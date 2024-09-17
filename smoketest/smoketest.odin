package smoketest

import "core:fmt"
import "core:net"
import "core:mem"
import "core:os"
import "core:strings"
import "core:thread"
import "core:time"
import "core:bytes"

ADDR :: "0.0.0.0"

ClientTask :: struct #align(4) {
    socket: ^net.TCP_Socket,
    clientEndpoint: net.Endpoint,
    clientID: i32
}

main :: proc() {
    when ODIN_DEBUG {
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)

        defer {
            if len(track.allocation_map) > 0 {
                fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
                for _, entry in track.allocation_map {
                    fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
                }
            }
            if len(track.bad_free_array) > 0 {
                fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
                for entry in track.bad_free_array {
                    fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
                }
            }
            mem.tracking_allocator_destroy(&track)
        }
    }

    addr, ok := net.parse_ip4_address(ADDR)
    endpoint : net.Endpoint
    endpoint.address = addr
    endpoint.port = 8888
    fmt.printfln("Starting server %s on port %v", ADDR, endpoint.port)
    socket, netErr := net.listen_tcp(endpoint)
    if netErr != nil {
        fmt.panicf("netErr: %s", netErr)
    }

    N :: 16
    pool : thread.Pool
    thread.pool_init(&pool, context.allocator, N)
    defer thread.pool_destroy(&pool)
    thread.pool_start(&pool)

    clientID : i32 = 0

    for {
        for thread.pool_num_done(&pool) > 0 {
            thread.pool_pop_done(&pool)
        }
        clientSock, clientEnd, acceptErr := net.accept_tcp(socket)
        if acceptErr != nil do fmt.panicf("acceptErr: %s", acceptErr)
        net.set_option(clientSock, .Receive_Timeout, time.Minute)
        task := ClientTask{clientEndpoint=clientEnd, socket=&clientSock, clientID=clientID}
        clientID += 1
        thread.pool_add_task(&pool, context.allocator, handleClientTask, &task)
    }
}

handleClientTask :: proc(task: thread.Task) {
    clientTask := transmute(^ClientTask)task.data
    client := clientTask.clientID
    socket := clientTask.socket^
    fmt.println("Handling new client:", client)
    for {
        data : [mem.Kilobyte*2]byte
        message : [dynamic]byte
        defer delete(message)
        n, recvErr := net.recv_tcp(socket, data[:])
        if recvErr != nil {
            fmt.printfln("Network Error: %s", recvErr)
            net.close(socket)
            return
        }
        if n == 0 {
            fmt.printfln("Connection %v closed", client)
            net.close(socket)
            return
        }
        for b, i in data {
            if i + 3 < len(data) - 1 && bytes.equal(data[i:i+3], {0, 0, 0}) {
                break
            }
            append(&message, b)
        }
        n1, sendErr := net.send_tcp(socket, message[:])
        if sendErr != nil {
            fmt.println("sendErr:", sendErr)
        }
    }
}
