class Solution {
    func solution(_ S: String) -> String {
        // STEP 1: Count how many times each digit appears
        // Think of it like sorting candies by color
        var digitCount = [Int](repeating: 0, count: 10)
        
        // Example: "39878" gives us:
        // digitCount[3] = 1
        // digitCount[7] = 1  
        // digitCount[8] = 2
        // digitCount[9] = 1
        for char in S {
            if let digit = Int(String(char)) {
                digitCount[digit] += 1
            }
        }
        
        // STEP 2: Build palindrome starting with biggest digits
        var firstHalf = ""      // Left side of palindrome
        var middleDigit = ""     // Center (can only use 1 digit)
        
        // Start from 9 and go down to 0 (we want BIGGEST number)
        for digit in stride(from: 9, through: 0, by: -1) {
            let count = digitCount[digit]
            
            // How many PAIRS can we make?
            // Example: if we have 5 eights, we can make 2 pairs (4 eights)
            let pairs = count / 2
            
            // Add these pairs to our first half
            // Example: 2 pairs of 8 → "88" goes to firstHalf
            if pairs > 0 {
                firstHalf += String(repeating: String(digit), count: pairs)
            }
            
            // Is there a leftover digit? Save the BIGGEST one for middle
            // Example: if we have 3 nines, we use 2 for pairs, save 1 for middle
            if count % 2 == 1 && middleDigit.isEmpty {
                middleDigit = String(digit)
            }
        }
        
        // STEP 3: Handle special cases
        
        // Case 1: All zeros like "0000" → return "0"
        if firstHalf.allSatisfy({ $0 == "0" }) && middleDigit == "0" {
            return "0"
        }
        
        // Case 2: Leading zeros problem
        // Example: "00900" would give us "00900" but we can't have leading zeros!
        // So we return just "9" (the middle digit)
        if firstHalf.first == "0" {
            if !middleDigit.isEmpty {
                return middleDigit  // Return single digit
            }
            return "0"
        }
        
        // STEP 4: Build the final palindrome
        // palindrome = firstHalf + middle + firstHalf reversed
        let secondHalf = String(firstHalf.reversed())
        let palindrome = firstHalf + middleDigit + secondHalf
        
        return palindrome
    }
}

// ==========================================
// VISUAL EXAMPLES TO UNDERSTAND
// ==========================================

let solution = Solution()

print("=== Example 1: '39878' ===")
print("Input digits: 3, 9, 8, 7, 8")
print("Count: 3→1, 7→1, 8→2, 9→1")
print("Pairs we can use: 8→1 pair (two 8s)")
print("Leftover for middle: 9 (biggest leftover)")
print("Build: '8' + '9' + '8' = '898'")
print("Result: \(solution.solution("39878"))\n")

print("=== Example 2: '00900' ===")
print("Input digits: 0, 0, 9, 0, 0")
print("Count: 0→4, 9→1")
print("Pairs we can use: 0→2 pairs (four 0s)")
print("Leftover for middle: 9")
print("Build: '00' + '9' + '00' = '00900' ❌ (leading zeros!)")
print("Fix: Return just '9'")
print("Result: \(solution.solution("00900"))\n")

print("=== Example 3: '129321' ===")
print("Input digits: 1, 2, 9, 3, 2, 1")
print("Count: 1→2, 2→2, 3→1, 9→1")
print("Pairs: 1→1 pair, 2→1 pair")
print("Middle: 9 (biggest odd count)")
print("Build from biggest: ")
print("  - No 9 pairs")
print("  - No 8,7,6,5,4 at all")
print("  - 3 has odd count (save for middle)")
print("  - 2 has 1 pair → firstHalf = '2'")
print("  - 1 has 1 pair → firstHalf = '21'")
print("Final: '21' + '3' + '12' = '21312'")
print("Result: \(solution.solution("129321"))\n")

// ==========================================
// HOW PALINDROMES WORK
// ==========================================
print("=== What is a Palindrome? ===")
print("A palindrome reads the same forwards and backwards:")
print("• 898 → 8-9-8 (same both ways ✓)")
print("• 12321 → 1-2-3-2-1 (same both ways ✓)")
print("• 123 → NOT a palindrome ✗")
print("\n=== Key Rules ===")
print("1. We can only use the digits we're given")
print("2. We want the LARGEST possible number")
print("3. No leading zeros (099 is not valid)")
print("4. For middle position, we can use only 1 digit")
