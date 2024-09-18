package primetime

import "core:fmt"
import "core:net"
import "core:thread"
import "core:time"
import "core:mem"
import "core:math"
import "core:strings"
import "core:strconv"

ADDR :: "0.0.0.0"

ClientTask :: struct {
    socket: ^net.TCP_Socket,
    clientEndpoint: net.Endpoint,
    clientID: i32
}

main :: proc() {
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
        net.set_option(clientSock, .Receive_Timeout, time.Second*30)
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
        result : [dynamic]string
        defer delete(result)
        append(&result, "{\"method\":\"")
        data : [mem.Kilobyte*2]byte
        message : [dynamic]byte
        defer delete(message)
        n, recvErr := net.recv_tcp(socket, data[:])
        if n == 0 {
            net.close(socket)
            return
        }
        for b in data {
            if b == 0 do continue
            if b == 10 do break
            append(&message, b)
        }
        reqStr := string(message[:])
        if reqStr[0] != '{' || reqStr[len(reqStr)-1] != '}' {
            net.send_tcp(socket, transmute([]byte)strings.join(result[:], ""))
            net.close(socket)
            return
        }
        f : []string = {"{", "}", ",", ":"}
        splitStr := strings.split_multi(reqStr, f[:])
        fmt.println(len(splitStr))
        numberI : int
        methodI : int
        for str, i in splitStr {
            if str == "\"number\"" do numberI = i + 1
            else if str == "\"method\"" do methodI = i + 1
        }
        if numberI == 0 || methodI == 0 || splitStr[methodI] != "\"isPrime\"" {
            net.send_tcp(socket, transmute([]byte)strings.join(result[:], ""))
            net.close(socket)
            return
        }
        append(&result, "isPrime")
        append(&result, "\",\"prime\":")
        number, parseErr := strconv.parse_i64(splitStr[numberI], 10)
        if parseErr == false {
            fmt.panicf("parseErr", parseErr, splitStr[numberI])
        }
        fmt.println("recv number, client:", number, client)
        if number < 0 {
            append(&result, "false}\n")
        } else {
            // fmt.println(isPrime(number), number)
            if isPrime(number) {
                append(&result, "true}\n")
            }
            else {
                append(&result, "false}\n")
            }
        }
        // time.sleep(time.Second)
        // fmt.println(strings.join(result[:], ""), number, client)
        net.send_tcp(socket, transmute([]byte)strings.join(result[:], ""))
    }
}

isPrime :: proc(num: i64) -> bool {
    if num < 2 do return false
    if num % 2 == 0 do return num == 2
    k : i64 = 3
    for k*k <= num {
        if num % k == 0 do return false
        k += 2
    }
    return true
}
