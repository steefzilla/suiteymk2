use suitey_rust_example::{add, multiply, is_even};

#[test]
fn test_integration_add_and_multiply() {
    let result = add(2, 3);
    assert_eq!(result, 5);

    let multiplied = multiply(result, 2);
    assert_eq!(multiplied, 10);
}

#[test]
fn test_integration_even_check() {
    let numbers = vec![1, 2, 3, 4, 5, 6];

    for &num in &numbers {
        let expected = num % 2 == 0;
        assert_eq!(is_even(num), expected, "Failed for number: {}", num);
    }
}

