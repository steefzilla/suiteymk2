/// A simple library for basic arithmetic operations
/// This is an example project for testing Suitey's Rust/Cargo detection

pub fn add(a: i32, b: i32) -> i32 {
    a + b
}

pub fn multiply(a: i32, b: i32) -> i32 {
    a * b
}

pub fn is_even(n: i32) -> bool {
    n % 2 == 0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_add() {
        assert_eq!(add(2, 3), 5);
        assert_eq!(add(-1, 1), 0);
        assert_eq!(add(0, 0), 0);
    }

    #[test]
    fn test_multiply() {
        assert_eq!(multiply(2, 3), 6);
        assert_eq!(multiply(-2, 3), -6);
        assert_eq!(multiply(0, 5), 0);
    }

    #[test]
    fn test_is_even() {
        assert!(is_even(2));
        assert!(is_even(0));
        assert!(is_even(-2));
        assert!(!is_even(1));
        assert!(!is_even(-1));
    }
}
