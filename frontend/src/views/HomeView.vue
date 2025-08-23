<template>
  <div class="full-page-container" @drop="handleDrop" @dragover.prevent>
    <a-layout>
      <a-layout-header class="header">
        <h1>哈希计算工具 {{ filePaths.length > 0 ? `已选择${filePaths.length}个项目` : '' }}</h1>
      </a-layout-header>

      <a-layout-content class="content">
        <!-- 主内容区使用flex布局 -->
        <div class="main-layout">
          <!-- 表格容器 - 自动计算高度 -->
          <div class="table-wrapper">
            <a-table
                :dataSource="tableData"
                :columns="dynamicColumns"
                :pagination="false"
                bordered
                size="small"
                :scroll="{ y: tableScrollHeight }"
                :rowClassName="(record, index) => (index % 2 === 1 ? 'table-row-dark' : '')"
            >
              <template
                  #customFilterDropdown="{ setSelectedKeys, selectedKeys, confirm, clearFilters, column }"
              >
                <div style="padding: 8px">
                  <a-input
                      ref="searchInput"
                      :placeholder="`搜索 ${column.title}`"
                      :value="selectedKeys[0]"
                      style="width: 188px; margin-bottom: 8px; display: block"
                      @change="e => setSelectedKeys(e.target.value ? [e.target.value] : [])"
                      @pressEnter="handleSearch(selectedKeys, confirm, column.dataIndex)"

                  />
                  <a-button
                      type="primary"
                      size="small"
                      style="width: 90px; margin-right: 8px"
                      @click="handleSearch(selectedKeys, confirm, column.dataIndex)"
                  >
                    <template #icon><SearchOutlined /></template>
                    搜索
                  </a-button>
                  <a-button size="small" style="width: 90px" @click="handleReset(clearFilters)">
                    重置
                  </a-button>
                </div>
              </template>
              <template #customFilterIcon="{ filtered }">
                <search-outlined :style="{ color: filtered ? '#108ee9' : undefined }" />
              </template>
              <template #bodyCell="{ column, record }">
                <template v-if="column.dataIndex.startsWith('hash_')">
                  <span>
                    {{ uppercase ? record[column.dataIndex].toUpperCase() : record[column.dataIndex] || '待计算' }}
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
                <template #icon><PlayCircleOutlined /></template>
                开始
              </a-button>
              <a-button danger @click="stopProcess" :disabled="!processing">
                <template #icon><PauseCircleTwoTone two-tone-color="#ff0000" /></template>
                停止
              </a-button>
              <a-button @click="clearResults">
                <template #icon><DeleteOutlined /></template>
                清除
              </a-button>
              <a-button type="dashed" @click="copyResults">
                <template #icon><CopyOutlined /></template>
                复制
              </a-button>
              <a-button type="dashed" @click="copyResults2">
                <template #icon><CopyOutlined /></template>
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
import {ref, reactive, computed, onMounted, onBeforeUnmount, watch} from 'vue';
import { message } from 'ant-design-vue';
import {
  PlayCircleOutlined,
  PauseCircleOutlined,
    PauseCircleTwoTone,
  DeleteOutlined,
  CopyOutlined,
  SearchOutlined,
} from '@ant-design/icons-vue';
import {CalHash, StopHash} from "../../wailsjs/go/main/App";
import {OnFileDrop} from "../../wailsjs/runtime/runtime.js";

// 模拟文件数据
const mockFiles = [
  { fileName: '', fileSize: '' },
  { fileName: '', fileSize: '' },
  { fileName: '', fileSize: '' },
  { fileName: '', fileSize: '' },
  { fileName: '', fileSize: '' },
  { fileName: '', fileSize: '' },
  { fileName: '', fileSize: '' },
  { fileName: '', fileSize: '' },
  { fileName: '', fileSize: '' },
  { fileName: '', fileSize: '' },
];


export default {
  components: {
    PlayCircleOutlined,
    PauseCircleOutlined,
    PauseCircleTwoTone,
    DeleteOutlined,
    CopyOutlined,
    SearchOutlined
  },
  setup() {
    // 算法选项
    const algorithmOptions = [
      { label: 'MD5', value: 'MD5' },
      { label: 'SHA1', value: 'SHA1' },
      { label: 'SHA256', value: 'SHA256' },
      { label: 'SHA512', value: 'SHA512' },
      { label: 'SM3', value: 'SM3' },
      { label: 'CRC32', value: 'CRC32' },
      { label: 'CRC64_ISO', value: 'CRC64_ISO' },
      { label: 'CRC64_ECMA', value: 'CRC64_ECMA' },
    ];
    const searchInput = ref()
    const state = reactive({
      searchText: '',
      searchedColumn: '',
    });
    const filePaths = ref([])
    const selectedAlgorithms = ref(['SHA256']);
    const uppercase = ref(true);
    const processing = ref(false);
    let processInterval = null;

    // 表格数据 - 根据选择的文件和算法动态生成
    const tableData = ref([]);

    // 动态列 - 根据选择的算法生成
    const dynamicColumns = computed(() => {
      const baseColumns = [
        { title: '文件名', dataIndex: 'fileName', key: 'fileName', width: 200, fixed: 'left' ,ellipsis: true,
          customFilterDropdown: true,
          onFilter: (value, record) => record.fileName.toString().toLowerCase().includes(value.toLowerCase()),
          onFilterDropdownOpenChange: visible => {
            if (visible) {
              setTimeout(() => {
                searchInput.value.focus();
              }, 100);
            }
          },},
        { title: '大小', dataIndex: 'fileSize', key: 'fileSize', width: 100 ,ellipsis: true},
      ];

      // 添加算法列
      const algorithmColumns = selectedAlgorithms.value.map(algorithm => ({
        title: algorithm,
        dataIndex: `hash_${algorithm.toLowerCase()}`,
        key: `hash_${algorithm.toLowerCase()}`,
        width: 250,
        customFilterDropdown: true,
        onFilter: (value, record) => record[`hash_${algorithm.toLowerCase()}`].toString().toLowerCase().includes(value.toLowerCase()),
        onFilterDropdownOpenChange: visible => {
          if (visible) {
            setTimeout(() => {
              searchInput.value.focus();
            }, 100);
          }
        },
      }));
      const fullPathColumn = [
        { title: '文件完整路径', dataIndex: 'filePath', key: 'filePath',width: 100,ellipsis: true},
      ]
      return [...baseColumns, ...algorithmColumns, ...fullPathColumn];
    });
    console.log(dynamicColumns.value)
    // 表格滚动高度
    const tableScrollHeight = ref(500);

    // 计算表格可用高度
    const calculateTableHeight = () => {
      const headerHeight = 64; // 头部高度
      const controlPanelHeight = 125; // 控制面板高度(根据实际内容调整)
      const margins = 48; // 边距总和

      tableScrollHeight.value = window.innerHeight - headerHeight - controlPanelHeight - margins;
    };

    // 初始化表格数据
    const initTableData = () => {
      tableData.value = mockFiles.map(file => {
        const row = { ...file };
        // 为每个算法初始化空值
        selectedAlgorithms.value.forEach(algorithm => {
          row[`hash_${algorithm.toLowerCase()}`] = '';
        });
        row['filePath'] = ''
        return row;
      });
    };

    // 开始处理
    const startProcess = () => {
      let option = {}
      selectedAlgorithms.value.map( algorithm => {
        option[algorithm] = true
      });
      if (selectedAlgorithms.value.length === 0) {
        message.warning('请至少选择1种算法');
        return;
      }
      if (filePaths.value.length === 0) {
        message.warning('请至少提供1个文件或目录');
        return;
      }
      CalHash(filePaths.value,JSON.stringify(option)).then((result,err)=>{
        // message.info(JSON.stringify(hashers))
        tableData.value = []
        result.forEach((hasher, index, array) => {
          const row = {}
          row['fileName'] = hasher['fileName']
          row['fileSize'] = hasher['fileSize']
          selectedAlgorithms.value.forEach(algorithm => {
            row[`hash_${algorithm.toLowerCase()}`] = hasher['hashResult'][algorithm];
          });
          row['filePath'] = hasher['filePath']
          tableData.value.push(row)
        })
        message.success("计算完成！")
        processing.value = false;
      })
      // 重新初始化数据
      initTableData();
      processing.value = true;
      message.info('开始计算哈希值...');
    };

    const stopProcess = () => {
      if (!processing.value) {
        message.warn("未进行计算！")
        return
      }
      StopHash()
      processing.value = false;
      message.info("已停止！")
    }

    const handleDrop = (e) => {
      OnFileDrop((x,y,paths)=>{
        if(paths.length > 0){
          filePaths.value = paths
        }
      },false)
    };
    const handleSearch = (selectedKeys, confirm, dataIndex) => {
      confirm();
      state.searchText = selectedKeys[0];
      state.searchedColumn = dataIndex;
    };
    const handleReset = clearFilters => {
      clearFilters({ confirm: true });
      state.searchText = '';
    };
    watch(selectedAlgorithms, (newAlgorithms, oldAlgorithms) => {
      // 找出新增的算法
      const addedAlgorithms = newAlgorithms.filter(
          algo => !oldAlgorithms.includes(algo)
      );

      if (addedAlgorithms.length > 0) {
        // 为新增算法初始化空值
        tableData.value = tableData.value.map(row => {
          const newRow = { ...row };
          addedAlgorithms.forEach(algorithm => {
            newRow[`hash_${algorithm.toLowerCase()}`] = '';
          });
          return newRow;
        });
      }
    }, { deep: true });

    // 清除结果
    const clearResults = () => {
      if (processing.value) {
        message.warning('请先停止计算');
        return;
      }

      initTableData();
      filePaths.value = []
      message.success('已清除所有结果');
    };

    // 复制结果
    const copyResults = () => {
      const headers = dynamicColumns.value.map(col => col.title).join('\t');
      const rows = tableData.value.map(row =>
          dynamicColumns.value.map(col => uppercase.value ? row[col.dataIndex].toUpperCase() : row[col.dataIndex]).join('\t')
      ).join('\n');

      const textToCopy = `${headers}\n${rows}`;

      navigator.clipboard.writeText(textToCopy)
          .then(() => message.success('已复制到剪贴板'))
          .catch(() => message.error('复制失败'));
    };

    // 复制结果
    const copyResults2 = () => {
      const headers = dynamicColumns.value.slice(0,dynamicColumns.value.length-1).map(col => {
        return col.title
      }).join('\t');
      const rows = tableData.value.map(row =>
            dynamicColumns.value.slice(0,dynamicColumns.value.length-1).map(col => uppercase.value ? row[col.dataIndex].toUpperCase() : row[col.dataIndex]).join('\t')
      ).join('\n');

      const textToCopy = `${headers}\n${rows}`;

      navigator.clipboard.writeText(textToCopy)
          .then(() => message.success('已复制到剪贴板'))
          .catch(() => message.error('复制失败'));
    };

    // 初始化
    onMounted(() => {
      initTableData();
      calculateTableHeight();

      window.addEventListener('resize', calculateTableHeight);
    });

    // 组件卸载前移除事件监听
    onBeforeUnmount(() => {
      window.removeEventListener('resize', calculateTableHeight);
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
.header {
  background: #fff;
  padding: 0 24px;
  box-shadow: 0 1px 4px rgba(0, 21, 41, 0.08);
  display: flex;
  align-items: center;
  height: 64px;
  flex-shrink: 0;
}

.header h1 {
  margin: 0;
  font-size: 18px;
}

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

/* 表格容器 */
.table-wrapper {
  flex: 1;
  min-height: 200px;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  margin-bottom: 16px;
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