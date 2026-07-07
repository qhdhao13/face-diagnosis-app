/**
 * 全局常量定义
 * 集中管理合规文案、存储键名、模型默认值
 */

/** 本地存储键名 */
export class StorageKeys {
  static readonly USER_PROFILE: string = 'user_profile';
  static readonly MODEL_CONFIG: string = 'model_config';
  static readonly MEMBER_AUTH: string = 'member_auth';
  static readonly PHONE_AUTH: string = 'phone_auth';
  static readonly NETWORK_AUTH: string = 'network_auth';
  static readonly DISCLAIMER_ACCEPTED: string = 'disclaimer_accepted';
  static readonly VERSION_IGNORE: string = 'version_ignore';
}

/** 合规固定免责声明 */
export class ComplianceTexts {
  static readonly STARTUP_DISCLAIMER: string =
    '本应用为传统中医古籍文化趣味自测工具，非医疗软件。所有内容仅为古人养生观察参考与生活调理科普，' +
    '不具备诊断、诊疗功能，不提供任何用药指导。自测结果仅供文化娱乐与日常养护参考，不具备医学参考价值。' +
    '继续使用本应用，即表示您已阅读并同意《隐私政策》与《免责声明》。' +
    '自测时面部照片将加密上传至您配置的 AI 服务进行分析，分析完成后不在服务器长期保存。' +
    '身体不适请及时前往正规医疗机构就诊。';

  static readonly REPORT_FOOTER: string =
    '【免责声明】本报告内容源自古籍养生文化解读，纯属趣味自测与生活参考，非医疗结论。' +
    '用户依据内容自行养护产生的一切后果由用户自行承担。';

  /** 四维养护方案引用说明 */
  static readonly WELLNESS_CITATION_NOTICE: string =
    '以下均为所引古籍原文摘录，仅供您自行查阅原典、自行理解；' +
    '本应用不对原文作延伸解读，亦不提供个性化养护指导或用药建议。';

  static readonly COMMERCIAL_NOTICE: string =
    '本应用所有代码、功能、文案、古籍解析内容均为开发者原创整理，禁止任何个人、团体私自复制、' +
    '篡改、二次分发、商业盈利使用。任何商用行为必须提前征得开发者书面同意。';

  static readonly DEVELOPER_WECHAT: string = 'qhdhao';
  static readonly DEVELOPER_EMAIL: string = 'qhdhao@126.com';

  static readonly PRIVACY_POLICY: string =
    '【隐私政策】\n' +
    '更新日期：2026-07-07\n' +
    '应用名称：古籍面诊养生\n' +
    '包名：com.face.diagnosis.app\n' +
    '开发者：qhdhao（qhdhao@126.com）\n\n' +
    '【应用权限说明】\n' +
    '本应用申请以下系统权限，均仅在您主动使用相关功能时生效；' +
    '未授权时对应功能不可用，不影响其他功能。\n' +
    '· 相机（ohos.permission.CAMERA，user_grant）：' +
    '用于在扫描页调用前置摄像头拍摄正脸照片，或配合相册选图完成气色文化自测；' +
    '照片仅用于本次分析，不会在本地长期保存。\n' +
    '· 网络（ohos.permission.INTERNET）：' +
    '用于将面部照片上传至您配置的 AI 服务或体验服进行分析；断网时使用本地规则兜底。\n' +
    '· 网络状态（ohos.permission.GET_NETWORK_INFO）：' +
    '仅用于检测设备是否联网，以便切换在线/离线模式。\n\n' +
    '【个人信息处理】\n' +
    '1. 自测时面部照片将上传至您配置的第三方 AI 服务（如通义千问）或开发者体验服进行外观分析，' +
    '仅用于生成文化自测参考，分析完成后应用内立即销毁本地副本，服务器不长期保存。\n' +
    '2. 手机号用于注册与体验配额统计，上传至开发者配置的服务器；昵称等基础信息仍仅存本地。\n' +
    '3. 体验免 Key 模式：面部照片经开发者服务器转发至 AI 分析（每日限次）；自带 Key 模式直连您配置的 AI 服务。\n' +
    '4. API Key 等配置信息仅保存在本地设备。\n\n' +
    '【其他说明】\n' +
    '1. 本应用为传统中医古籍文化趣味自测工具，不提供医疗诊断、诊疗或用药指导服务。\n' +
    '2. 继续使用本应用即视为同意本政策及《免责声明》。\n' +
    '3. 如有疑问请联系：qhdhao@126.com。';
}

/** 医疗敏感词黑名单（自动风控过滤，30+ 词） */
export class SensitiveWords {
  static readonly BLOCK_LIST: string[] = [
    '诊断', '确诊', '病症', '治疗', '治愈', '治病', '开药', '病灶', '病情',
    '疾病', '辨证', '虚症', '实症', '处方', '用药', '疗效', '医案', '方剂',
    '病理', '临床', '症状', '患者', '医嘱', '手术', '化疗', '放疗',
    '化验', '检查', '指标', '异常', '病变'
  ];
}

/** 默认官方推荐模型配置（部署时替换为通义千问 / 智谱等 OpenAI 兼容 endpoint） */
export class DefaultModelConfig {
  /**
   * 通义千问 OpenAI 兼容模式（需在设置页或此处配置有效 apiKey）
   * 文档: https://help.aliyun.com/zh/model-studio/
   */
  static readonly OFFICIAL_ENDPOINT: string =
    'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions';
  /** 文案生成模型 */
  static readonly OFFICIAL_MODEL_NAME: string = 'qwen-turbo';
  /** 云端视觉多模态模型（看脸） */
  static readonly OFFICIAL_VISION_MODEL_NAME: string = 'qwen-vl-plus';
  static readonly OFFICIAL_TIP: string =
    '自带 Key：填写通义等 API Key。体验免 Key：须手机号注册且在白名单内，每日 2 次免费。';
}

/** 体验服务器与手机号白名单（Key 仅存服务端，不在 App 内） */
export class ExperienceServerConfig {
  /**
   * 腾讯云轻量服务器（体验免 Key 代理）
   * 部署目录：tools/experience-server，默认端口 8787
   */
  static readonly BASE_URL: string = 'http://49.232.232.27:8787';
  static readonly REGISTER_PATH: string = '/v1/auth/register';
  static readonly STATUS_PATH: string = '/v1/auth/status';
  static readonly CONSUME_PATH: string = '/v1/quota/consume';
  static readonly VISION_PATH: string = '/v1/vision/analyze';
  static readonly TEXT_PATH: string = '/v1/text/generate';
  /** 25色部 Lab 云端分析（图片与数据存服务器） */
  static readonly REGION25_ANALYZE_PATH: string = '/v1/region25/analyze';
  static readonly REGION25_REPORT_PATH: string = '/v1/region25/report';
  static readonly REGION25_IMAGE_PATH: string = '/v1/region25/image';
  /** 白名单用户每日免费完整自测次数 */
  static readonly DAILY_FREE_LIMIT: number = 2;
  static readonly PHONE_HINT: string =
    '请先注册手机号。体验免 Key 须开发者白名单，每日 2 次；自带 Key 须注册但不限次数。';
}

/** 远程 API 默认地址（部署时替换为真实服务端点） */
export class RemoteApiConfig {
  static readonly VERSION_CHECK_ENDPOINT: string =
    'https://api.openai-compatible.example.com/app/version';
  static readonly HTTP_TIMEOUT_MS: number = 15000;
}

/** 应用版本信息 */
export class AppVersion {
  static readonly CURRENT: string = '1.0.0';
  static readonly CODE: number = 1000000;
}

/**
 * 会员内测配置（方案 A）
 * 以 VIP_ 前缀的会员 ID 自动审批，仅供开发者发放的内测账号使用
 */
export class MemberConfig {
  /** 内测会员 ID 前缀，注册时以此开头则自动通过审批 */
  static readonly VIP_PREFIX: string = 'VIP_';
  /** 会员 ID 最短长度 */
  static readonly MIN_ID_LENGTH: number = 4;
  /** 内测说明（设置页展示） */
  static readonly VIP_TEST_HINT: string =
    '内测会员：请向开发者索取以 VIP_ 开头的会员 ID（如 VIP_张三），' +
    '注册后立即通过，即可使用私有模型。非 VIP_ 前缀需等待后台审批（当前未开放）。';
}

/** 古籍数据源标识 */
export class AncientSources {
  static readonly LINGSHU_WUSE: string = '《黄帝内经·灵枢·五色》';
  static readonly WANGZHEN_ZUNJING: string = '《望诊遵经》';
  static readonly WANG_HONGMO: string = '王鸿谟《中医色诊学》';
}

/** 面部分区名称 */
export class FaceRegions {
  static readonly REGIONS: string[] = [
    '额头', '左脸颊', '右脸颊', '鼻部', '下巴', '眼周', '唇部'
  ];
}

/** 气色描述词库（客观外观，非医疗） */
export class ComplexionTypes {
  static readonly TYPES: string[] = [
    '偏白', '偏黄', '偏红', '偏暗沉', '偏青白', '暗沉', '泛红', '浮肿', '细纹', '气色尚可'
  ];
}
