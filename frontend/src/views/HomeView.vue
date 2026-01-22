<template>
    <div class="full-page-container" @drop="handleDrop" @dragover.prevent>
        <a-layout>
            <a-layout-content class="content">
                <!-- 主内容区使用flex布局 -->
                <div class="main-layout">
                    <!-- 进度条 -->
                    <div class="progress-container" v-if="processing">
                        <a-progress :percent="progressPercentage" status="active" :show-info="true" />
                    </div>

                    <!-- 表格容器 - 自动计算高度 -->
                    <div class="table-wrapper">
                        <a-table :dataSource="tableData" :columns="dynamicColumns" :pagination="false" bordered
                            size="small" :scroll="{ x: 'max-content', y: tableScrollHeight }" :rowClassName="(record, index) =>
                                index % 2 === 1 ? 'table-row-dark' : ''
                                ">
                            <template #customFilterDropdown="{
                                setSelectedKeys,
                                selectedKeys,
                                confirm,
                                clearFilters,
                                column,
                            }">
                                <div style="padding: 8px">
                                    <a-input ref="searchInput" :placeholder="`搜索 ${column.title}`"
                                        :value="selectedKeys[0]" style="
                                            width: 188px;
                                            margin-bottom: 8px;
                                            display: block;
                                        " @change="
                                            (e) =>
                                                setSelectedKeys(
                                                    e.target.value
                                                        ? [e.target.value]
                                                        : [],
                                                )
                                        " @pressEnter="
                                            handleSearch(
                                                selectedKeys,
                                                confirm,
                                                column.dataIndex,
                                            )
                                            " />
                                    <a-button type="primary" size="small" style="width: 90px; margin-right: 8px" @click="
                                        handleSearch(
                                            selectedKeys,
                                            confirm,
                                            column.dataIndex,
                                        )
                                        ">
                                        <template #icon>
                                            <SearchOutlined />
                                        </template>
                                        搜索
                                    </a-button>
                                    <a-button size="small" style="width: 90px" @click="handleReset(clearFilters)">
                                        重置
                                    </a-button>
                                </div>
                            </template>
                            <template #customFilterIcon="{ filtered }">
                                <search-outlined :style="{
                                    color: filtered ? '#108ee9' : undefined,
                                }" />
                            </template>
                            <template #bodyCell="{ column, record }">
                                <template v-if="column.dataIndex.startsWith('hash_')">
                                    <span>
                                        {{
                                            uppercase
                                                ? record[
                                                    column.dataIndex
                                                ].toUpperCase()
                                                : record[column.dataIndex] ||
                                                "待计算"
                                        }}
                                    </span>
                                </template>
                            </template>
                        </a-table>
                    </div>

                    <!-- 控制面板 - 固定高度 -->
                    <div class="control-panel">
                        <div class="options-group">
                            <a-checkbox-group v-model:value="selectedAlgorithms" :options="algorithmOptions" />
                            <a-checkbox v-model:checked="uppercase">结果大写</a-checkbox>
                        </div>

                        <div class="button-group">
                            <a-button type="primary" @click="startProcess" :loading="processing">
                                <template #icon>
                                    <PlayCircleOutlined />
                                </template>
                                开始
                            </a-button>
                            <a-button danger @click="stopProcess" :disabled="!processing">
                                <template #icon>
                                    <PauseCircleTwoTone two-tone-color="#ff0000" />
                                </template>
                                停止
                            </a-button>
                            <a-button @click="clearResults">
                                <template #icon>
                                    <DeleteOutlined />
                                </template>
                                清除
                            </a-button>
                            <a-button type="dashed" @click="copyResults">
                                <template #icon>
                                    <CopyOutlined />
                                </template>
                                复制
                            </a-button>
                            <a-button type="dashed" @click="copyResults2">
                                <template #icon>
                                    <CopyOutlined />
                                </template>
                                复制（不带完整路径）
                            </a-button>
                        </div>
                    </div>
                </div>
            </a-layout-content>
        </a-layout>
    </div>
</template>

<script>
import {
    ref,
    reactive,
    computed,
    onMounted,
    onBeforeUnmount,
    watch,
} from "vue";
import { message } from "ant-design-vue";
import {
    PlayCircleOutlined,
    PauseCircleOutlined,
    PauseCircleTwoTone,
    DeleteOutlined,
    CopyOutlined,
    SearchOutlined,
} from "@ant-design/icons-vue";
import { CalHash, StopHash } from "../../wailsjs/go/main/App";
import { OnFileDrop, EventsOn } from "../../wailsjs/runtime/runtime.js";

// 模拟文件数据
const mockFiles = Array.from({ length: 50 }, () => ({ fileName: "", fileSize: "" }));

export default {
    components: {
        PlayCircleOutlined,
        PauseCircleOutlined,
        PauseCircleTwoTone,
        DeleteOutlined,
        CopyOutlined,
        SearchOutlined,
    },
    setup() {
        // 算法选项
        const algorithmOptions = [
            { label: "MD5", value: "MD5" },
            { label: "SHA1", value: "SHA1" },
            { label: "SHA256", value: "SHA256" },
            { label: "SHA512", value: "SHA512" },
            { label: "SM3", value: "SM3" },
            { label: "CRC32", value: "CRC32" },
            { label: "CRC64_ISO", value: "CRC64_ISO" },
            { label: "CRC64_ECMA", value: "CRC64_ECMA" },
        ];
        const searchInput = ref();
        const state = reactive({
            searchText: "",
            searchedColumn: "",
        });
        const filePaths = ref([]);
        const selectedAlgorithms = ref(["SHA256"]);
        const uppercase = ref(true);
        const processing = ref(false);
        let processInterval = null;

        // 表格数据 - 根据选择的文件和算法动态生成
        const tableData = ref([]);

        // 进度条相关变量
        const progressPercentage = ref(0);
        const totalFiles = ref(0);
        const completedFiles = ref(0);

        // 动态列 - 根据选择的算法生成
        const dynamicColumns = computed(() => {
            const baseColumns = [
                {
                    title: "文件名",
                    dataIndex: "fileName",
                    key: "fileName",
                    width: 200,
                    maxWidth: 500,
                    fixed: "left",
                    wordWrap: true,
                    customFilterDropdown: true,
                    onFilter: (value, record) =>
                        record.fileName
                            .toString()
                            .toLowerCase()
                            .includes(value.toLowerCase()),
                    onFilterDropdownOpenChange: (visible) => {
                        if (visible) {
                            setTimeout(() => {
                                searchInput.value.focus();
                            }, 100);
                        }
                    },
                },
                {
                    title: "大小",
                    dataIndex: "fileSize",
                    key: "fileSize",
                    width: 100,
                    maxWidth: 150,
                    wordWrap: true,
                },
            ];

            // 添加算法列
            const algorithmColumns = selectedAlgorithms.value.map(
                (algorithm) => ({
                    title: algorithm,
                    dataIndex: `hash_${algorithm.toLowerCase()}`,
                    key: `hash_${algorithm.toLowerCase()}`,
                    width: 250,
                    maxWidth: 350,
                    wordWrap: true,
                    customFilterDropdown: true,
                    onFilter: (value, record) =>
                        record[`hash_${algorithm.toLowerCase()}`]
                            .toString()
                            .toLowerCase()
                            .includes(value.toLowerCase()),
                    onFilterDropdownOpenChange: (visible) => {
                        if (visible) {
                            setTimeout(() => {
                                searchInput.value.focus();
                            }, 100);
                        }
                    },
                }),
            );
            const fullPathColumn = [
                {
                    title: "文件完整路径",
                    dataIndex: "filePath",
                    key: "filePath",
                    width: 300,
                    maxWidth: 800,
                    wordWrap: true,
                },
            ];
            return [...baseColumns, ...algorithmColumns, ...fullPathColumn];
        });
        console.log(dynamicColumns.value);
        // 表格滚动高度
        const tableScrollHeight = ref(500);

        let computedFiles = 0;
        EventsOn("FILEDONE", (filePath, fileSize, data, totalFilesCount) => {
            computedFiles++;
            console.log(filePath, fileSize, data, totalFilesCount);

            // 更新进度条（使用防抖）
            totalFiles.value = totalFilesCount;
            completedFiles.value = computedFiles;
            if (totalFilesCount > 0) {
                const percentage = Math.round((computedFiles / totalFilesCount) * 100);
                updateProgressDebounced(percentage);
            }

            const row = {};
            row["fileName"] = filePath.split("\\").pop();
            row["fileSize"] = fileSize;
            selectedAlgorithms.value.forEach((algorithm) => {
                row[`hash_${algorithm.toLowerCase()}`] =
                    data[algorithm];
            });
            row["filePath"] = filePath;
            tableData.value.push(row);
        })

        // 计算表格可用高度
        const calculateTableHeight = () => {
            const controlPanelHeight = 125; // 控制面板高度(根据实际内容调整)
            const margins = 48; // 边距总和

            tableScrollHeight.value =
                window.innerHeight -
                controlPanelHeight -
                margins;
        };

        // 初始化表格数据
        const initTableData = () => {
            tableData.value = [];
            tableData.value = mockFiles.map((file) => {
                const row = { ...file };
                // 为每个算法初始化空值
                selectedAlgorithms.value.forEach((algorithm) => {
                    row[`hash_${algorithm.toLowerCase()}`] = "";
                });
                row["filePath"] = "";
                return row;
            });
        };

        // 防抖函数
        const debounce = (func, wait) => {
            let timeout;
            return function (...args) {
                clearTimeout(timeout);
                timeout = setTimeout(() => func.apply(this, args), wait);
            };
        };

        // 防抖处理的进度条更新函数
        const updateProgressDebounced = debounce((percentage) => {
            progressPercentage.value = percentage;
        }, 80); // 100ms防抖延迟

        // 开始处理
        const startProcess = () => {
            tableData.value = [];

            // 重置进度条
            computedFiles = 0;
            progressPercentage.value = 0;
            totalFiles.value = 0;
            completedFiles.value = 0;

            let option = {};
            selectedAlgorithms.value.map((algorithm) => {
                option[algorithm] = true;
            });
            if (selectedAlgorithms.value.length === 0) {
                message.warning("请至少选择1种算法");
                return;
            }
            if (filePaths.value.length === 0) {
                message.warning("请至少提供1个文件或目录");
                return;
            }
            const start = performance.now();
            CalHash(filePaths.value, JSON.stringify(option)).then(
                (result, err) => {
                    const end = performance.now();
                    const elapsed = end - start; // 毫秒数（高精度）
                    console.log(`耗时: ${elapsed.toFixed(3)}ms`);
                    // 确保最终进度为100%
                    progressPercentage.value = 100;
                    message.success(`计算完成！耗时: ${elapsed.toFixed(3)}ms`);
                    processing.value = false;
                },
            );
            processing.value = true;
            message.info("开始计算哈希值...");
        };

        const stopProcess = () => {
            if (!processing.value) {
                message.warn("未进行计算！");
                return;
            }
            StopHash();
            processing.value = false;
            message.info("已停止！");
        };

        const handleDrop = (e) => {
            OnFileDrop((x, y, paths) => {
                if (paths.length > 0) {
                    filePaths.value = paths;

                    // 将文件名填入表格占位
                    tableData.value = paths.map((filePath) => {
                        const row = {};
                        // 提取文件名（不包含路径）
                        const fileName = filePath.split('\\').pop().split('/').pop();
                        row["fileName"] = fileName;
                        row["fileSize"] = "等待开始";
                        // 为每个算法初始化空值
                        selectedAlgorithms.value.forEach((algorithm) => {
                            row[`hash_${algorithm.toLowerCase()}`] = "";
                        });
                        row["filePath"] = filePath;
                        return row;
                    });
                }
            }, false);
        };
        const handleSearch = (selectedKeys, confirm, dataIndex) => {
            confirm();
            state.searchText = selectedKeys[0];
            state.searchedColumn = dataIndex;
        };
        const handleReset = (clearFilters) => {
            clearFilters({ confirm: true });
            state.searchText = "";
        };
        watch(
            selectedAlgorithms,
            (newAlgorithms, oldAlgorithms) => {
                // 找出新增的算法
                const addedAlgorithms = newAlgorithms.filter(
                    (algo) => !oldAlgorithms.includes(algo),
                );

                if (addedAlgorithms.length > 0) {
                    // 为新增算法初始化空值
                    tableData.value = tableData.value.map((row) => {
                        const newRow = { ...row };
                        addedAlgorithms.forEach((algorithm) => {
                            newRow[`hash_${algorithm.toLowerCase()}`] = "";
                        });
                        return newRow;
                    });
                }
            },
            { deep: true },
        );

        // 清除结果
        const clearResults = () => {
            if (processing.value) {
                message.warning("请先停止计算");
                return;
            }

            initTableData();
            filePaths.value = [];
            message.success("已清除所有结果");
        };

        // 复制结果
        const copyResults = () => {
            const headers = dynamicColumns.value
                .map((col) => col.title)
                .join("\t");
            const rows = tableData.value
                .map((row) =>
                    dynamicColumns.value
                        .map((col) =>
                            uppercase.value
                                ? row[col.dataIndex].toUpperCase()
                                : row[col.dataIndex],
                        )
                        .join("\t"),
                )
                .join("\n");

            const textToCopy = `${headers}\n${rows}`;

            navigator.clipboard
                .writeText(textToCopy)
                .then(() => message.success("已复制到剪贴板"))
                .catch(() => message.error("复制失败"));
        };

        // 复制结果
        const copyResults2 = () => {
            const headers = dynamicColumns.value
                .slice(0, dynamicColumns.value.length - 1)
                .map((col) => {
                    return col.title;
                })
                .join("\t");
            const rows = tableData.value
                .map((row) =>
                    dynamicColumns.value
                        .slice(0, dynamicColumns.value.length - 1)
                        .map((col) =>
                            uppercase.value
                                ? row[col.dataIndex].toUpperCase()
                                : row[col.dataIndex],
                        )
                        .join("\t"),
                )
                .join("\n");

            const textToCopy = `${headers}\n${rows}`;

            navigator.clipboard
                .writeText(textToCopy)
                .then(() => message.success("已复制到剪贴板"))
                .catch(() => message.error("复制失败"));
        };

        // 初始化
        onMounted(() => {
            initTableData();
            calculateTableHeight();

            window.addEventListener("resize", calculateTableHeight);
        });

        // 组件卸载前移除事件监听
        onBeforeUnmount(() => {
            window.removeEventListener("resize", calculateTableHeight);
            if (processInterval) clearInterval(processInterval);
        });

        return {
            tableData,
            dynamicColumns,
            algorithmOptions,
            selectedAlgorithms,
            uppercase,
            tableScrollHeight,
            processing,
            filePaths,
            progressPercentage,
            startProcess,
            handleDrop,
            clearResults,
            copyResults,
            copyResults2,
            stopProcess,
            handleSearch,
            handleReset,
            searchInput,
        };
    },
};
</script>

<style scoped>
/* 全屏容器 */
.full-page-container {
    height: 100vh;
    width: 100vw;
    display: flex;
    flex-direction: column;
}

/* 布局样式 */

.content {
    flex: 1;
    overflow: hidden;
    display: flex;
}

/* 主布局 */
.main-layout {
    flex: 1;
    display: flex;
    flex-direction: column;
    padding: 5px;
    overflow: hidden;
}

/* 斑马纹效果 */
.table-row-dark {
    background-color: #fafafa;
}

/* 进度条容器 */
.progress-container {
    margin-bottom: 10px;
    padding: 10px;
    background: #fafafa;
    border-radius: 4px;
}

/* 表格容器 */
.table-wrapper {
    flex: 1;
    height: 100%;
    overflow: hidden;
    display: flex;
    flex-direction: column;
}

/* 控制面板 */
.control-panel {
    padding: 16px;
    border: 1px solid #f0f0f0;
    border-radius: 4px;
    background: #fff;
    flex-shrink: 0;
}

/* 表格样式调整 */
:deep(.ant-table) {
    flex: 1;
    display: flex;
    flex-direction: column;
}

:deep(.ant-table-container) {
    flex: 1;
    display: flex;
    flex-direction: column;
}

:deep(.ant-table-body) {
    overflow: auto !important;
    word-break: break-all;
}

:deep(.ant-table-cell) {
    white-space: normal;
    word-break: break-all;
}

/* 滚动条样式优化 */
:deep(::-webkit-scrollbar) {
    width: 6px;
    height: 6px;
}

:deep(::-webkit-scrollbar-track) {
    background: #f1f1f1;
    border-radius: 3px;
}

:deep(::-webkit-scrollbar-thumb) {
    background: #c1c1c1;
    border-radius: 3px;
}

:deep(::-webkit-scrollbar-thumb:hover) {
    background: #a8a8a8;
}

/* 响应式调整 */
@media (max-width: 768px) {
    .main-content {
        padding: 12px;
    }

    .options-group {
        flex-direction: column;
        gap: 8px;
    }

    .button-group {
        justify-content: space-between;
    }

    .button-group button {
        flex: 1;
        min-width: 100px;
    }
}
</style>
