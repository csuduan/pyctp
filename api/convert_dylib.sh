#!/bin/bash
# convert_framework_to_dylib.sh
# 用法: ./convert_framework_to_dylib.sh MyFramework.framework

if [ $# -ne 1 ]; then
    echo "用法: $0 <framework_path>"
    exit 1
fi

FRAMEWORK="$1"
BASENAME=$(basename "$FRAMEWORK" .framework)
OUTPUT="lib${BASENAME}.dylib"

echo "转换: $FRAMEWORK -> $OUTPUT"

# 1. 找到真正的库文件
if [ -f "$FRAMEWORK/$BASENAME" ]; then
    # 直接拷贝
    cp "$FRAMEWORK/$BASENAME" "$OUTPUT"
    echo "✓ 提取库文件"
elif [ -L "$FRAMEWORK/$BASENAME" ]; then
    # 解析符号链接
    REAL_PATH=$(readlink "$FRAMEWORK/$BASENAME")
    if [[ $REAL_PATH == /* ]]; then
        cp "$REAL_PATH" "$OUTPUT"
    else
        cp "$FRAMEWORK/$REAL_PATH" "$OUTPUT"
    fi
    echo "✓ 从符号链接提取"
else
    # 尝试在 Versions 中查找
    if [ -f "$FRAMEWORK/Versions/Current/$BASENAME" ]; then
        cp "$FRAMEWORK/Versions/Current/$BASENAME" "$OUTPUT"
        echo "✓ 从 Versions/Current 提取"
    elif [ -f "$FRAMEWORK/Versions/A/$BASENAME" ]; then
        cp "$FRAMEWORK/Versions/A/$BASENAME" "$OUTPUT"
        echo "✓ 从 Versions/A 提取"
    else
        echo "❌ 找不到库文件"
        exit 1
    fi
fi

# 2. 修改 install name
echo "修改 install name..."
OLD_ID=$(otool -D "$OUTPUT" | tail -1)
NEW_ID="@rpath/$OUTPUT"
if [ "$OLD_ID" != "$NEW_ID" ]; then
    install_name_tool -id "$NEW_ID" "$OUTPUT"
    echo "✓ install name: $OLD_ID -> $NEW_ID"
fi

# 3. 修改依赖路径
echo "更新依赖路径..."
otool -L "$OUTPUT" | grep "$BASENAME.framework" | while read -r line; do
    OLD_PATH=$(echo "$line" | awk '{print $1}')
    if [[ $OLD_PATH == *"$BASENAME.framework"* ]]; then
        NEW_PATH="@rpath/$OUTPUT"
        install_name_tool -change "$OLD_PATH" "$NEW_PATH" "$OUTPUT"
        echo "✓ 更新: $OLD_PATH -> $NEW_PATH"
    fi
done

# 4. 重新签名
echo "重新签名..."
codesign --force --sign - $OUTPUT

echo ""
echo "✅ 转换完成: $OUTPUT"
echo "使用:"
echo "  otool -L $OUTPUT"
echo "  file $OUTPUT"