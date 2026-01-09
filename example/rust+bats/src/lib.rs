pub fn combined_add(a: i32, b: i32) -> i32 {
    a + b
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_combined_add() {
        assert_eq!(combined_add(1, 2), 3);
    }
}
