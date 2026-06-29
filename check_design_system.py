import re
import os

def get_constants(file_path):
    with open(file_path, 'r') as f:
        content = f.read()

    spacings = re.findall(r'static let (s\d+|screenHorizontalMargin|sectionVerticalSpacing)', content)
    corners = re.findall(r'static let (\w+): CGFloat', content) # Simplified
    # Actually let's just get all words after 'static let'
    constants = re.findall(r'static let (\w+)', content)
    return set(constants)

def check_usages(file_path, constants):
    with open(file_path, 'r') as f:
        content = f.read()

    # Find all DesignSystem.Something.constant
    usages = re.findall(r'DesignSystem\.(\w+)\.(\w+)', content)
    for category, constant in usages:
        if constant not in constants:
            print(f"Error in {file_path}: DesignSystem.{category}.{constant} not found in DesignSystem.swift")

design_constants = get_constants('ios/MBGC/DesignSystem.swift')
print(f"Constants found: {design_constants}")

for root, dirs, files in os.walk('ios/MBGC'):
    for file in files:
        if file.endswith('.swift'):
            check_usages(os.path.join(root, file), design_constants)
