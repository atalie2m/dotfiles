use std::collections::HashSet;

pub(crate) fn file_minus_file(left: &[String], right: &[String]) -> Vec<String> {
    if left.is_empty() {
        return Vec::new();
    }

    if right.is_empty() {
        return left.to_vec();
    }

    let right_set: HashSet<&str> = right.iter().map(String::as_str).collect();
    left.iter()
        .filter(|item| !right_set.contains(item.as_str()))
        .cloned()
        .collect()
}

pub(crate) fn file_intersection(left: &[String], right: &[String]) -> Vec<String> {
    if left.is_empty() || right.is_empty() {
        return Vec::new();
    }

    let left_set: HashSet<&str> = left.iter().map(String::as_str).collect();
    right
        .iter()
        .filter(|item| left_set.contains(item.as_str()))
        .cloned()
        .collect()
}

pub(crate) fn unique_lines(lines: &[String]) -> Vec<String> {
    let mut seen = HashSet::new();
    let mut unique = Vec::new();

    for line in lines {
        if seen.insert(line.clone()) {
            unique.push(line.clone());
        }
    }

    unique
}
