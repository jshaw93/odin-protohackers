package primetime

import "core:fmt"
import "core:net"
import "core:thread"
import "core:time"
import "core:mem"
import "core:strings"
import "core:unicode/utf8"
import "core:encoding/json"

ADDR :: "0.0.0.0"

ClientTask :: struct {
    socket: ^net.TCP_Socket,
    clientEndpoint: net.Endpoint,
    clientID: i32
}

Request :: struct{
    method: string,
    number: union {i64, f64}
}

Response :: struct {
    method: string,
    prime: bool
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
    INVALID :string: "nonsense"
    for {
        data : [mem.Kilobyte*16]byte
        n, recvErr := net.recv_tcp(socket, data[:])
        if recvErr != nil {
            if recvErr == net.TCP_Recv_Error.Connection_Closed {
                net.close(socket)
                fmt.println("socket closed", client)
                return
            }
            fmt.panicf("recvErr", recvErr)
        }
        if n == 0 {
            net.close(socket)
            fmt.println("socket closed:", client)
            return
        }
        fmt.println(n)
        currentI : int = 0
        EOF : bool = false
        for !EOF {
            req : Request
            res : Response
            res.method = "isPrime"
            handlerArr : [dynamic]byte
            defer delete(handlerArr)
            for b, i in data[currentI:n] {
                if b == 10 {
                    currentI += i + 1
                    break
                }
                append(&handlerArr, b)
            }
            if len(handlerArr) < 1 || handlerArr[0] == 0 {
                EOF = true
                continue
            }
            unmarshalErr := json.unmarshal(handlerArr[:], &req)
            if unmarshalErr != nil {
                fmt.println("invalid json", string(handlerArr[:]))
                net.send_tcp(socket, transmute([]byte)INVALID)
                fmt.println("Closing connection", client)
                net.close(socket)
                return
            }
            if req.number == nil || req.method != "isPrime" {
                fmt.println("invalid fields", req)
                net.send_tcp(socket, transmute([]byte)INVALID)
                fmt.println("Closing connection", client)
                net.close(socket)
                return
            }
            fmt.println("valid", req)
            switch v in req.number {
                case i64:
                    res.prime = isPrime(req.number.(i64))
                    d, err := json.marshal(res)
                    if err != nil {
                        fmt.println("err1", err)
                    }
                    d1 := string(d[:])
                    d2 : []string = {d1, "\n"}
                    d3 := strings.concatenate(d2)
                    // fmt.println("Sending", d3)
                    n1, err1 := net.send_tcp(socket, transmute([]byte)d3)
                    if err1 != nil {
                        fmt.println(err1)
                    }
                    continue
                case f64:
                    res.prime = false
                    b, err := json.marshal(res)
                    if err != nil {
                        fmt.println("err2", err)
                    }
                    d1 := string(b[:])
                    d2 : []string = {d1, "\n"}
                    d3 := strings.concatenate(d2)
                    // fmt.println("Sending", d3)
                    n1, err1 := net.send_tcp(socket, transmute([]byte)d3)
                    if err1 != nil {
                        fmt.println(err1)
                    }
                    continue
                case:
                    fmt.println("invalid number", req)
                    net.send_tcp(socket, transmute([]byte)INVALID)
                    fmt.println("Closing connection", client)
                    net.close(socket)
                    return
            }
        }
        EOF = false
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
