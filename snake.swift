// RUN ME IN A TERMINAL WINDOW

import Darwin

struct Coord {
    let x: Int
    let y: Int
}

// ah, for TupleLiteralConvertible
extension Coord: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: Int...) {
        precondition(elements.count == 2)
        x = elements[0]
        y = elements[1]
    }
}

func +(lhs: Coord, rhs: Coord)->Coord {
    return Coord(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
}

func -(lhs: Coord, rhs: Coord)->Coord {
    return Coord(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
}

extension Coord: Equatable { }

func ==(lhs: Coord, rhs: Coord)->Bool {
    return lhs.x == rhs.x && lhs.y == rhs.y
}

func ~=(pattern: [Coord], value: Coord) -> Bool {
    return pattern.contains(value)
}

enum Direction {
    case Left, Right, Forward
}

enum Orientation {
    case Up, Down, Left, Right
}

typealias Movement = (Coord, Orientation)

extension Orientation {
    var coord: Coord {
        switch self {
        case .Up:    return [ 0,-1]
        case .Down:  return [ 0, 1]
        case .Left:  return [-1, 0]
        case .Right: return [ 1, 0]
        }
    }

    var movement: Movement { return (self.coord, self) }
    
    func move(direction: Direction) -> Orientation {
        switch (self, direction) {
        case (_, .Forward):                    return self
        case (.Up, .Left), (.Down, .Right):    return .Left
        case (.Down, .Left), (.Up, .Right):    return .Right
        case (.Left, .Right), (.Right, .Left): return .Up
        case (.Left, .Left), (.Right, .Right): return .Down
        }
    }
}

public struct Snake {
    let tail: [Coord]
    let head: Coord
    let locations: [Coord]

    init (head: Coord, tail: [Coord]) {
        self.head = head
        self.tail = tail
        self.locations = [head] + tail.reduce([]) {
            segments, segment in segments + [(segments.last ?? head) - segment]
        }
    }
}

extension Snake {
    func grow(to: Coord) -> Snake {
        return Snake(head: head + to, tail: [to] + tail)
    }
    
    func wriggle(to: Coord) -> Snake {
        return Snake(head: head + to, tail: [to] + tail.dropLast())
    }
}

public struct Board {
    let snake: Snake
    let orientation: Orientation
    let appleLocation: Coord
    let size: Coord
    
    init(snake: Snake, orientation: Orientation, appleLocation: Coord? = nil, size: Coord = [25,15]) {
        self.snake = snake
        self.orientation = orientation
        self.appleLocation =  appleLocation ?? [Int(arc4random()) % size.x, Int(arc4random()) % size.y]
        self.size = size
    }
}

extension Board {
    func advanceSnake(d: Direction) -> Board {
        let (delta, newOrientation) = orientation.move(direction: d).movement
        let newLocation = snake.head + delta
        
        // grow the snake if it ate the apple
        let newSnake =
        appleLocation == newLocation
            ? snake.grow(to: delta)
            : snake.wriggle(to: delta)
        
        let newAppleLocation: Coord? =
        newLocation == appleLocation
            ? nil
            : appleLocation
        
        return Board(snake: newSnake,
            orientation: newOrientation,
            appleLocation: newAppleLocation)
    }
}

extension Board: CustomStringConvertible {
    public var description: String {
        let fillSquare = { (square: Coord) -> Character in
            switch square {
            case self.snake.locations: return "*"
            case self.appleLocation: return ""
            default: return " "
            }
        }
        
        let squares: [String] = (0..<self.size.y).map { y in
            let line = (0..<self.size.x).map { x in
                fillSquare([x,y])
            }
            return "|\(String(line))|"
        }
        
        let header = ["+" + String(repeating: "-", count: self.size.x) + "+"]
        return (header + squares + header).joined(separator: "\n")
    }
}

extension Board {
    var wallCrash: Bool {
        let width: Range = 0..<size.x
        let height: Range = 0..<size.y
        return !width.contains(snake.head.x) || !height.contains(snake.head.y)
    }
    
    var tailCrash: Bool {
        return snake.locations.dropFirst().contains(snake.head)
    }
}

func getChar(timeout: Double) -> Character {
    // OK so maybe this particular function isn't so immutable
    
    assert(timeout < (Double(UInt8.max) * 100), "timeout too long")
    
    var oldt: termios = termios(c_iflag: 0, c_oflag: 0, c_cflag: 0, c_lflag: 0,
        c_cc: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            cc_t(2), 0, 0, 0),
        c_ispeed: 0, c_ospeed: 0)
    
    tcgetattr(STDIN_FILENO, &oldt)
    
    var newt = oldt
    
    newt.c_lflag ^= UInt(ICANON) | UInt(ECHO)
    
    // it's a bit annoying that this is a tuple not an array
    // as it means you can't use the defined constants (like
    // VMIN and VTIME, that we need here) to address specific
    // elements.
    newt.c_cc.16 = 0
    // VTIME is in tenths of a second
    newt.c_cc.17 = UInt8(timeout/100.0)
    
    tcsetattr( STDIN_FILENO, TCSANOW, &newt)
    
    var buffer = [0]
    read(STDIN_FILENO, &buffer, 4);
    
    let key = buffer[0]
    let ascii: UInt32 = key > 0 ? UInt32(key) : 32 // = " "
    
    tcsetattr( STDIN_FILENO, TCSANOW, &oldt)
    
    // I'm guessing there's a shorter way here:
    return Character(UnicodeScalar(ascii) ?? " ")
}


func play(board: Board, countdown: Double) -> Board {
    
    if board.wallCrash {
        print("Wall crash!")
        exit(0)
    }
    
    if board.tailCrash {
        print("Tail crash!")
        exit(0)
    }
    
    print(board)
    
    let dir: Direction
    switch getChar(timeout: countdown) {
    case "a": dir = .Left
    case "s": dir = .Right
    default:  dir = .Forward
    }
    
    return board.advanceSnake(d: dir)
}

let snake = Snake(head: [2,2], tail: [[1,0], [1,0]])
let board = Board(snake: snake, orientation: .Right)

// this stride represents the starting difficulty and ramp-up
let countdown = stride(from: 700.0, through: 0.0, by: -0.5)

print("A to turn left, S to turn right")

countdown.reduce(board, play)

