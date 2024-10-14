package primetime

import "core:fmt"
import "core:net"
import "core:thread"
import "core:time"
import "core:mem"
import "core:strings"
import "core:unicode/utf8"
import "core:encoding/json"
import "core:strconv"

ADDR :: "0.0.0.0"

ClientTask :: struct {
    socket: net.TCP_Socket,
    clientEndpoint: net.Endpoint,
    clientID: i32
}

Request :: struct{
    method: string,
    number: union {i64, f64, string}
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
        net.set_option(clientSock, .Receive_Buffer_Size, mem.Kilobyte*32)
        net.set_option(clientSock, .Linger, time.Second*15)
        net.set_option(clientSock, .Keep_Alive, true)
        task := new_clone(ClientTask{clientEndpoint=clientEnd, socket=clientSock, clientID=clientID})
        clientID += 1
        thread.pool_add_task(&pool, context.allocator, handleClientTask, task)
    }
}

handleClientTask :: proc(task: thread.Task) {
    clientTask := transmute(^ClientTask)task.data
    client := clientTask.clientID
    socket : net.TCP_Socket = clientTask.socket
    fmt.println("Handling new client:", client)
    INVALID :string: "nonsense"

    for {
        data := make([]byte, mem.Kilobyte*32)
        n, recvErr := net.recv_tcp(socket, data)
        if recvErr != nil {
            if recvErr == net.TCP_Recv_Error.Connection_Closed {
                net.close(socket)
                fmt.println("socket closed", client)
                return
            }
            fmt.panicf("recvErr", recvErr, client)
        }
        if n == 0 {
            net.close(socket)
            fmt.println("socket closed:", client)
            return
        }
        bounds : int
        iterateBefore := 0 // Left window pointer
        iterateAfter := 0 // Right window pointer
        iterateData : for {
            if data[0] != 123 {
                fmt.println("invalid first byte", data[0])
                net.send_tcp(socket, transmute([]byte)INVALID)
                fmt.println("Closing connection", client)
                net.close(socket)
                return
            }
            req : Request
            res : Response
            res.method = "isPrime"
            _tmp := data[iterateBefore:n]
            for b, i in _tmp {
                if b == 10 {
                    iterateAfter += 1
                    break
                }
                iterateAfter += 1
            }
            if iterateBefore == n do break iterateData
            numsAreStrings : [dynamic]i64
            defer delete(numsAreStrings)
            splitChars : []string = {"{", ",", ":", "}"}
            strHandle := strings.split_multi(string(data[iterateBefore:iterateAfter]), splitChars)
            // if client >= 6 do fmt.println(string(handlerArr[:]), client)
            for i, index in strHandle {
                if i == "\"number\"" {
                    checkNumber : string = strHandle[index+1]
                    if checkNumber[0] == '\"' && checkNumber[len(checkNumber)-1] == '\"' {
                        parsed, parseErr := strconv.parse_i64(checkNumber[1:len(checkNumber)-1])
                        if !parseErr {
                            continue
                        }
                        append(&numsAreStrings, parsed)
                    }
                }
            }
            unmarshalErr := json.unmarshal(data[iterateBefore:iterateAfter], &req, json.Specification.JSON5)
            if unmarshalErr != nil {
                fmt.println("invalid json", string(data[iterateBefore:iterateAfter]))
                net.send_tcp(socket, transmute([]byte)INVALID)
                fmt.println("Closing connection", client)
                net.close(socket)
                return
            }
            iterateBefore = iterateAfter // Move left window pointer to current
            for num in numsAreStrings {
                if req.number == num {
                    buf : [258]u8
                    numInt := int(num)
                    req.number = strconv.itoa(buf[:], numInt)
                    break
                }
            }
            if req.number == nil || req.method != "isPrime" {
                fmt.println("invalid fields", req)
                net.send_tcp(socket, transmute([]byte)INVALID)
                fmt.println("Closing connection", client)
                net.close(socket)
                return
            }
            // if client >= 6 do fmt.println("valid", req, client)
            switch v in req.number {
                case i64:
                    res.prime = isPrime(req.number.(i64))
                    opt : json.Marshal_Options
                    opt.spec = json.Specification.JSON5
                    d, err := json.marshal(res, opt)
                    if err != nil {
                        fmt.println("err1", err)
                    }
                    d1 := string(d[:])
                    d2 : []string = {d1, "\n"}
                    d3 := strings.concatenate(d2)
                    // fmt.println("Sending", d3)
                    n1, err1 := net.send_tcp(socket, transmute([]byte)d3)
                    if err1 != nil {
                        if err1 == net.TCP_Send_Error.Connection_Closed {
                            net.close(socket)
                            fmt.println("Socket closed", client)
                            return
                        }
                        fmt.println(err1)
                    }
                    continue
                case f64:
                    res.prime = false
                    opt : json.Marshal_Options
                    opt.spec = json.Specification.JSON5
                    b, err := json.marshal(res, opt)
                    if err != nil {
                        fmt.println("err2", err)
                    }
                    d1 := string(b[:])
                    d2 : []string = {d1, "\n"}
                    d3 := strings.concatenate(d2)
                    // fmt.println("Sending", d3)
                    n1, err1 := net.send_tcp(socket, transmute([]byte)d3)
                    if err1 != nil {
                        if err1 == net.TCP_Send_Error.Connection_Closed {
                            net.close(socket)
                            fmt.println("Socket closed", client)
                            return
                        }
                        fmt.println(err1)
                    }
                    continue
                case string:
                    fmt.println("invalid number: string", req)
                    net.send_tcp(socket, transmute([]byte)INVALID)
                    fmt.println("Closing connection", client)
                    net.close(socket)
                    return
                case:
                    fmt.println("invalid number", req)
                    net.send_tcp(socket, transmute([]byte)INVALID)
                    fmt.println("Closing connection", client)
                    net.close(socket)
                    return
            }
        }
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
