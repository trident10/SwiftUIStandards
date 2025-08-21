class Solution {
    func solution(_ S: String) -> String {
        // STEP 1: Count how many times each digit appears
        var digitCount = [Int](repeating: 0, count: 10)
        
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
            let pairs = count / 2
            
            // Add these pairs to our first half
            if pairs > 0 {
                firstHalf += String(repeating: String(digit), count: pairs)
            }
            
            // Save the BIGGEST leftover digit for middle
            if count % 2 == 1 && middleDigit.isEmpty {
                middleDigit = String(digit)
            }
        }
        
        // STEP 3: Handle special cases
        
        // Case: No pairs at all, only single digits
        // Example: "54321" → return biggest digit "5"
        if firstHalf.isEmpty {
            return middleDigit.isEmpty ? "0" : middleDigit
        }
        
        // Case: Leading zeros problem
        // Example: "00900" → firstHalf="00", middle="9"
        // We can't have "00900", so return "9"
        if firstHalf.allSatisfy({ $0 == "0" }) {
            // If we only have zero pairs
            if !middleDigit.isEmpty && middleDigit != "0" {
                return middleDigit  // Return the non-zero middle digit
            }
            return "0"  // All zeros case: "0000" → "0"
        }
        
        // STEP 4: Build the final palindrome
        let secondHalf = String(firstHalf.reversed())
        let palindrome = firstHalf + middleDigit + secondHalf
        
        return palindrome
    }
}

// ==========================================
// TEST CASES WITH DETAILED TRACING
// ==========================================

let solution = Solution()

print("=== Test 1: '39878' ===")
print("Step-by-step:")
print("  Counts: 3→1, 7→1, 8→2, 9→1")
print("  Pairs: 8→1 pair")
print("  firstHalf: '8'")
print("  middleDigit: '9' (biggest odd count)")
print("  Result: '8' + '9' + '8' = '898'")
print("  Actual: \(solution.solution("39878"))")
print()

print("=== Test 2: '00900' ===")
print("Step-by-step:")
print("  Counts: 0→4, 9→1")
print("  Pairs: 0→2 pairs")
print("  firstHalf: '00'")
print("  middleDigit: '9'")
print("  firstHalf is all zeros? YES")
print("  middleDigit is not '0'? YES")
print("  Return just middleDigit: '9'")
print("  Actual: \(solution.solution("00900"))")
print()

print("=== Test 3: '0000' ===")
print("Step-by-step:")
print("  Counts: 0→4")
print("  Pairs: 0→2 pairs")
print("  firstHalf: '00'")
print("  middleDigit: '' (even count, no leftover)")
print("  firstHalf is all zeros? YES")
print("  middleDigit is empty? YES")
print("  Return: '0'")
print("  Actual: \(solution.solution("0000"))")
print()

print("=== Test 4: '54321' ===")
print("Step-by-step:")
print("  Counts: 1→1, 2→1, 3→1, 4→1, 5→1")
print("  Pairs: none (all single digits)")
print("  firstHalf: '' (empty)")
print("  middleDigit: '5' (biggest)")
print("  firstHalf is empty? YES")
print("  Return middleDigit: '5'")
print("  Actual: \(solution.solution("54321"))")
print()

print("=== Test 5: '129321' ===")
print("Step-by-step:")
print("  Counts: 1→2, 2→2, 3→1, 9→1")
print("  Processing from 9 to 0:")
print("    9: 0 pairs, save for middle")
print("    3: 0 pairs, skip (already have 9 for middle)")
print("    2: 1 pair → firstHalf = '2'")
print("    1: 1 pair → firstHalf = '21'")
print("  Result: '21' + '9' + '12' = '21912'")
print("  Actual: \(solution.solution("129321"))")
print()

print("=== Additional Edge Cases ===")
print("'000': \(solution.solution("000"))") // Should be "0"
print("'00000': \(solution.solution("00000"))") // Should be "0"
print("'001': \(solution.solution("001"))") // Should be "1"
print("'0012200': \(solution.solution("0012200"))") // Should be "20102"
