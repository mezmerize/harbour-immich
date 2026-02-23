import QtQuick 2.0
import Sailfish.Silica 1.0

Canvas {
   id: qrCanvas

   property string text: ""
   property color foregroundColor: Theme.primaryColor
   property color backgroundColor: "white"
   property int margin: 4

   onTextChanged: requestPaint()
   onForegroundColorChanged: requestPaint()
   onBackgroundColorChanged: requestPaint()
   onWidthChanged: requestPaint()
   onHeightChanged: requestPaint()

   onPaint: {
       var ctx = getContext("2d")
       ctx.fillStyle = backgroundColor
       ctx.fillRect(0, 0, width, height)

       if (text.length === 0) return

       var qr = generateQR(text)
       if (!qr) return

       var moduleCount = qr.length
       var size = Math.min(width, height)
       var moduleSize = Math.floor((size - 2 * margin) / moduleCount)
       var offset = Math.floor((size - moduleCount * moduleSize) / 2)

       ctx.fillStyle = foregroundColor
       for (var row = 0; row < moduleCount; row++) {
           for (var col = 0; col < moduleCount; col++) {
               if (qr[row][col]) {
                   ctx.fillRect(offset + col * moduleSize, offset + row * moduleSize, moduleSize, moduleSize)
               }
           }
       }
   }

   // Pre-computed format info strings for EC Level L (index 0) and masks 0-7
   // Format: [ecLevel][mask] -> 15-bit format string
   property var formatInfoStrings: [
       // L level, masks 0-7
       [0x77c4, 0x72f3, 0x7daa, 0x789d, 0x662f, 0x6318, 0x6c41, 0x6976],
       // M level, masks 0-7
       [0x5412, 0x5125, 0x5e7c, 0x5b4b, 0x45f9, 0x40ce, 0x4f97, 0x4aa0],
       // Q level, masks 0-7
       [0x355f, 0x3068, 0x3f31, 0x3a06, 0x24b4, 0x2183, 0x2eda, 0x2bed],
       // H level, masks 0-7
       [0x1689, 0x13be, 0x1ce7, 0x19d0, 0x0762, 0x0255, 0x0d0c, 0x083b]
   ]

   function generateQR(inputText) {
       var version = 1
       var ecLevel = 0 // L level

       // Find minimum version
       var dataCapacity = [17, 32, 53, 78, 106, 134, 154, 192, 230, 271]
       for (var v = 0; v < dataCapacity.length; v++) {
           if (inputText.length <= dataCapacity[v]) {
               version = v + 1
               break
           }
       }
       if (inputText.length > dataCapacity[dataCapacity.length - 1]) {
           version = 10
       }

       var size = version * 4 + 17
       var modules = createMatrix(size)
       var isFunction = createMatrix(size)

       // Place function patterns
       placeFunctionPatterns(modules, isFunction, version, size)

       // Encode data
       var data = encodeDataBytes(inputText, version)
       var ecData = addECC(data, version)

       // Place data bits
       placeDataBits(modules, isFunction, ecData, size)

       // Find best mask
       var bestMask = 0
       var bestPenalty = Infinity
       for (var mask = 0; mask < 8; mask++) {
           var testModules = copyMatrix(modules)
           applyMaskPattern(testModules, isFunction, mask, size)
           placeFormatBits(testModules, ecLevel, mask, size)
           var penalty = calculatePenalty(testModules, size)
           if (penalty < bestPenalty) {
               bestPenalty = penalty
               bestMask = mask
           }
       }

       // Apply best mask
       applyMaskPattern(modules, isFunction, bestMask, size)
       placeFormatBits(modules, ecLevel, bestMask, size)

       return modules
   }

   function createMatrix(size) {
       var m = []
       for (var i = 0; i < size; i++) {
           m[i] = []
           for (var j = 0; j < size; j++) {
               m[i][j] = false
           }
       }
       return m
   }

   function copyMatrix(m) {
       var copy = []
       for (var i = 0; i < m.length; i++) {
           copy[i] = m[i].slice()
       }
       return copy
   }

   function placeFunctionPatterns(modules, isFunction, version, size) {
       // Finder patterns
       placeFinderPattern(modules, isFunction, 0, 0)
       placeFinderPattern(modules, isFunction, size - 7, 0)
       placeFinderPattern(modules, isFunction, 0, size - 7)

       // Timing patterns
       for (var i = 8; i < size - 8; i++) {
           var val = (i % 2 === 0)
           modules[6][i] = val
           modules[i][6] = val
           isFunction[6][i] = true
           isFunction[i][6] = true
       }

       // Alignment patterns for version >= 2
       if (version >= 2) {
           var alignPos = getAlignmentPositions(version)
           for (var ai = 0; ai < alignPos.length; ai++) {
               for (var aj = 0; aj < alignPos.length; aj++) {
                   var ay = alignPos[ai]
                   var ax = alignPos[aj]
                   // Skip if overlaps with finder patterns
                   if ((ax <= 8 && ay <= 8) || (ax <= 8 && ay >= size - 9) || (ax >= size - 9 && ay <= 8))
                       continue
                   placeAlignmentPattern(modules, isFunction, ax, ay)
               }
           }
       }

       // Reserve format info areas
       for (var fi = 0; fi < 9; fi++) {
           isFunction[fi][8] = true
           isFunction[8][fi] = true
       }
       for (var fi2 = size - 8; fi2 < size; fi2++) {
           isFunction[fi2][8] = true
           isFunction[8][fi2] = true
       }

       // Dark module
       modules[size - 8][8] = true
       isFunction[size - 8][8] = true
   }

   function placeFinderPattern(modules, isFunction, startRow, startCol) {
       for (var r = -1; r <= 7; r++) {
           for (var c = -1; c <= 7; c++) {
               var row = startRow + r
               var col = startCol + c
               if (row < 0 || col < 0 || row >= modules.length || col >= modules.length) continue

               var black = (r >= 0 && r <= 6 && (c === 0 || c === 6)) ||
                           (c >= 0 && c <= 6 && (r === 0 || r === 6)) ||
                           (r >= 2 && r <= 4 && c >= 2 && c <= 4)
               modules[row][col] = black
               isFunction[row][col] = true
           }
       }
   }

   function placeAlignmentPattern(modules, isFunction, cx, cy) {
       for (var dy = -2; dy <= 2; dy++) {
           for (var dx = -2; dx <= 2; dx++) {
               var black = Math.abs(dx) === 2 || Math.abs(dy) === 2 || (dx === 0 && dy === 0)
               modules[cy + dy][cx + dx] = black
               isFunction[cy + dy][cx + dx] = true
           }
       }
   }

   function getAlignmentPositions(version) {
       if (version === 1) return []
       var numAlign = Math.floor(version / 7) + 2
       var step = version === 32 ? 26 : Math.ceil((version * 4 + 4) / (numAlign - 1) / 2) * 2
       var result = [6]
       for (var pos = version * 4 + 10; result.length < numAlign; pos -= step) {
           result.splice(1, 0, pos)
       }
       return result
   }

   function encodeDataBytes(inputText, version) {
       var bits = []

       // Mode indicator: byte mode = 0100
       bits.push(0, 1, 0, 0)

       // Character count (8 bits for versions 1-9)
       var len = inputText.length
       for (var i = 7; i >= 0; i--) {
           bits.push((len >> i) & 1)
       }

       // Data
       for (var j = 0; j < inputText.length; j++) {
           var charCode = inputText.charCodeAt(j)
           for (var k = 7; k >= 0; k--) {
               bits.push((charCode >> k) & 1)
           }
       }

       // Total data capacity for versions 1-10 at EC level L
       var dataCapacityBits = [152, 272, 440, 640, 864, 1088, 1248, 1552, 1856, 2192]
       var totalBits = dataCapacityBits[version - 1]

       // Terminator (up to 4 zeros)
       var terminatorLen = Math.min(4, totalBits - bits.length)
       for (var t = 0; t < terminatorLen; t++) {
           bits.push(0)
       }

       // Pad to byte boundary
       while (bits.length % 8 !== 0) {
           bits.push(0)
       }

       // Pad bytes (0xEC, 0x11 alternating)
       var padBytes = [0xEC, 0x11]
       var padIdx = 0
       while (bits.length < totalBits) {
           var pb = padBytes[padIdx % 2]
           for (var pi = 7; pi >= 0; pi--) {
               bits.push((pb >> pi) & 1)
           }
           padIdx++
       }

       // Convert to bytes
       var bytes = []
       for (var bi = 0; bi < bits.length; bi += 8) {
           var bv = 0
           for (var bj = 0; bj < 8; bj++) {
               bv = (bv << 1) | bits[bi + bj]
           }
           bytes.push(bv)
       }

       return bytes
   }

   function addECC(data, version) {
       // EC codewords per block for versions 1-10 at EC level L
       var ecPerBlock = [7, 10, 15, 20, 26, 18, 20, 24, 30, 18]
       var numEcCodewords = ecPerBlock[version - 1]

       // Total codewords for versions 1-10
       var totalCodewords = [26, 44, 70, 100, 134, 172, 196, 242, 292, 346]
       var numDataCodewords = totalCodewords[version - 1] - numEcCodewords

       // For simplicity, use single block for small versions
       var dataBlock = data.slice(0, numDataCodewords)
       while (dataBlock.length < numDataCodewords) {
           dataBlock.push(0)
       }

       var ecBlock = reedSolomonEncode(dataBlock, numEcCodewords)

       // Combine data and EC
       var result = dataBlock.concat(ecBlock)
       return result
   }

   function reedSolomonEncode(data, numEc) {
       // GF(256) with primitive polynomial 0x11d
       var gfExp = new Array(512)
       var gfLog = new Array(256)
       var x = 1
       for (var i = 0; i < 255; i++) {
           gfExp[i] = x
           gfLog[x] = i
           x <<= 1
           if (x >= 256) x ^= 0x11d
       }
       for (var j = 255; j < 512; j++) {
           gfExp[j] = gfExp[j - 255]
       }

       // Generate generator polynomial
       var gen = [1]
       for (var g = 0; g < numEc; g++) {
           var newGen = []
           for (var ngi = 0; ngi < gen.length + 1; ngi++) newGen.push(0)
           for (var gi = 0; gi < gen.length; gi++) {
               newGen[gi] ^= gen[gi]
               newGen[gi + 1] ^= gfExp[gfLog[gen[gi]] + g]
           }
           gen = newGen
       }

       // Polynomial division
       var remainder = data.slice()
       for (var r = 0; r < numEc; r++) {
           remainder.push(0)
       }

       for (var di = 0; di < data.length; di++) {
           var coef = remainder[di]
           if (coef !== 0) {
               var logCoef = gfLog[coef]
               for (var gi2 = 0; gi2 < gen.length; gi2++) {
                   remainder[di + gi2] ^= gfExp[gfLog[gen[gi2]] + logCoef]
               }
           }
       }

       return remainder.slice(data.length)
   }

   function placeDataBits(modules, isFunction, data, size) {
       var bits = []
       for (var i = 0; i < data.length; i++) {
           for (var j = 7; j >= 0; j--) {
               bits.push((data[i] >> j) & 1)
           }
       }

       var bitIdx = 0
       for (var right = size - 1; right >= 1; right -= 2) {
           if (right === 6) right = 5

           for (var vert = 0; vert < size; vert++) {
               for (var j2 = 0; j2 < 2; j2++) {
                   var x = right - j2
                   var upward = ((right + 1) & 2) === 0
                   var y = upward ? size - 1 - vert : vert

                   if (!isFunction[y][x] && bitIdx < bits.length) {
                       modules[y][x] = bits[bitIdx] === 1
                       bitIdx++
                   }
               }
           }
       }
   }

   function applyMaskPattern(modules, isFunction, mask, size) {
       for (var y = 0; y < size; y++) {
           for (var x = 0; x < size; x++) {
               if (isFunction[y][x]) continue

               var invert = false
               switch (mask) {
                   case 0: invert = (y + x) % 2 === 0; break
                   case 1: invert = y % 2 === 0; break
                   case 2: invert = x % 3 === 0; break
                   case 3: invert = (y + x) % 3 === 0; break
                   case 4: invert = (Math.floor(y / 2) + Math.floor(x / 3)) % 2 === 0; break
                   case 5: invert = y * x % 2 + y * x % 3 === 0; break
                   case 6: invert = (y * x % 2 + y * x % 3) % 2 === 0; break
                   case 7: invert = ((y + x) % 2 + y * x % 3) % 2 === 0; break
               }
               if (invert) modules[y][x] = !modules[y][x]
           }
       }
   }

   function placeFormatBits(modules, ecLevel, mask, size) {
       var formatVal = formatInfoStrings[ecLevel][mask]

       // Place format bits around top-left finder
       for (var i = 0; i <= 5; i++) {
           modules[i][8] = ((formatVal >> (14 - i)) & 1) === 1
       }
       modules[7][8] = ((formatVal >> 8) & 1) === 1
       modules[8][8] = ((formatVal >> 7) & 1) === 1
       modules[8][7] = ((formatVal >> 6) & 1) === 1
       for (var j = 0; j <= 5; j++) {
           modules[8][5 - j] = ((formatVal >> j) & 1) === 1
       }

       // Place format bits around top-right and bottom-left finders
       for (var k = 0; k <= 7; k++) {
           modules[8][size - 1 - k] = ((formatVal >> k) & 1) === 1
       }
       for (var l = 0; l <= 6; l++) {
           modules[size - 1 - l][8] = ((formatVal >> (14 - l)) & 1) === 1
       }
   }

   function calculatePenalty(modules, size) {
       var penalty = 0

       // Rule 1: runs of same color
       for (var y = 0; y < size; y++) {
           var runLength = 1
           for (var x = 1; x < size; x++) {
               if (modules[y][x] === modules[y][x-1]) {
                   runLength++
               } else {
                   if (runLength >= 5) penalty += runLength - 2
                   runLength = 1
               }
           }
           if (runLength >= 5) penalty += runLength - 2
       }
       for (var x2 = 0; x2 < size; x2++) {
           var runLength2 = 1
           for (var y2 = 1; y2 < size; y2++) {
               if (modules[y2][x2] === modules[y2-1][x2]) {
                   runLength2++
               } else {
                   if (runLength2 >= 5) penalty += runLength2 - 2
                   runLength2 = 1
               }
           }
           if (runLength2 >= 5) penalty += runLength2 - 2
       }

       // Rule 2: 2x2 blocks
       for (var y3 = 0; y3 < size - 1; y3++) {
           for (var x3 = 0; x3 < size - 1; x3++) {
               var c = modules[y3][x3]
               if (c === modules[y3][x3+1] && c === modules[y3+1][x3] && c === modules[y3+1][x3+1]) {
                   penalty += 3
               }
           }
       }

       return penalty
   }
}



