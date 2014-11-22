import Darwin

struct Coord {
    let x: Int
    let y: Int
}

// ah for TupleLiteralConvertible
extension Coord: ArrayLiteralConvertible {
    init(arrayLiteral elements: Int...) {
        assert(elements.count == 2)
        x = elements.first!
        y = elements.last!
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
  return contains(pattern,value)
}

enum Direction {
    case Left, Right, Forward
}

enum Orientation {
    case Up, Down, Left, Right
}

func move(o: Orientation, d: Direction) -> (Coord,Orientation) {
    switch (o,d) {
    case (.Up, .Forward):     return ([ 0,-1],.Up)
    case (.Up, .Left):        return ([-1, 0],.Left)
    case (.Up, .Right):       return ([ 1, 0],.Right)
    case (.Down, .Forward):   return ([ 0, 1],.Down)
    case (.Down, .Left):      return ([ 1, 0],.Right)
    case (.Down, .Right):     return ([-1, 0],.Left)
    case (.Left, .Forward):   return ([-1, 0],.Left)
    case (.Left, .Left):      return ([ 0, 1],.Down)
    case (.Left, .Right):     return ([ 0,-1],.Up)
    case (.Right, .Forward):  return ([ 1, 0],.Right)
    case (.Right, .Left):     return ([ 0,-1],.Up)
    case (.Right, .Right):    return ([ 0, 1],.Down)
    }
}

public struct Snake {
    let tail: [Coord]
}

extension Snake {
    func locationsFrom(head: Coord) -> [Coord] {
        return reduce(self.tail, [head]) { (snake, segment) in
            if let previous = snake.last {
                return snake + [previous - segment]
            }
            else {
                return snake
            }
        }
    }
}

public struct Board {
    let snake: Snake
    let headLocation: Coord
    let orientation: Orientation
    let appleLocation: Coord
    let size: Int
    
    var snakeLocations: [Coord] { 
      return snake.locationsFrom(headLocation) 
    }
    
    init(snake: Snake, headLocation: Coord, orientation: Orientation, appleLocation: Coord? = nil, size: Int = 15) {
      self.snake = snake
      self.headLocation = headLocation
      self.orientation = orientation
      self.appleLocation =  appleLocation ?? [Int(arc4random()) % size, Int(arc4random()) % size]
      self.size = size
    }
}

extension Board {
    func advanceSnake(d: Direction) -> Board {
        let (delta,newOrientation) = move(orientation, d)
        let newLocation = headLocation + delta
        
        // grow the snake if it ate the apple
        let newTail = [delta] + (appleLocation == newLocation ? snake.tail : Array(dropLast(snake.tail)))
        let newSnake = Snake(tail: newTail)
        
        let newAppleLocation: Coord? =
        newLocation == appleLocation
            ? nil
            : appleLocation
        
        return Board(snake: newSnake,
            headLocation: newLocation,
            orientation: newOrientation,
            appleLocation: newAppleLocation,
            size: size)
    }
}

extension Board: Printable {
    public var description: String {
        let snakeLocations = self.snakeLocations
        let fillSquare = { (square: Coord) -> Character in          
          switch square {
            case snakeLocations: return "*"
            case self.appleLocation: return ""
            default: return " "
          }          
        }
        
        let squares = map(0..<self.size) { (y: Int) -> String in
            let line = map(0..<self.size) { (x: Int) -> Character in
                return fillSquare([x,y])
            }
            return "|\(String(line))|"
        }
        
        let header = ["+" + String(Array(count: self.size, repeatedValue: "-")) + "+"]
        return "\n".join(header + squares + header)
    }
}

extension Board {
    func wallCrash() -> Bool {
        return !(0..<size).contains(headLocation.x) || !(0..<size).contains(headLocation.y)
    }
    
    func tailCrash() -> Bool {
        let locations = snake.locationsFrom(headLocation)
        return contains(dropFirst(locations)) { (segment: Coord)->Bool in
            segment == self.headLocation
        }
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
  let n = read(STDIN_FILENO, &buffer, 4);

  let key = buffer[0]
  let ascii: UInt32 = key > 0 ? UInt32(key) : 32 // = " "

  tcsetattr( STDIN_FILENO, TCSANOW, &oldt)
  
  // I'm guessing there's a shorter way here:
  return Character(UnicodeScalar(ascii))
}

func play(board: Board, countdown: Double) -> Board {
  
  if board.wallCrash() {
    println("Wall crash!")
    exit(0)
  }
  
  if board.tailCrash() {
    println("Tail crash!")
    exit(0)
  }

  println(board.description)
  
  let direction = { ()->Direction in
    // switches need to be expressions!
    switch getChar(countdown) {
       case "a": return .Left
       case "s": return .Right
       default: return .Forward
     }
  }()

  // hope for TCO, or a stack bigger than 
  // the longest possible snake
  return board.advanceSnake(direction)
}

let snake = Snake(tail: [[1,0],[1,0]])
let board = Board(snake: snake, 
              headLocation: [2,2], 
              orientation: .Right, 
              appleLocation: [4,4], 
              size: 15)

// this stride represents the starting difficulty and rampup
let countdown = stride(from: 500.0, through: 0.0, by: -0.25) 

println("A to turn right, S to turn left")
reduce(countdown, board, play)

// TODO: Add command-line params for all the things
