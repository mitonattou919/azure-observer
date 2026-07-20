// 共有型定義。命名規則・必須タグの型をここに集約する。
// パターン: {type}-{workload}-{env}-{instance} (CAFリソース略語 + サービス識別子 + 環境 + 連番)

@export()
type environment = 'prd' | 'stg' | 'dev'

@export()
@minLength(3)
@maxLength(3)
type workloadCode = string

@export()
@minLength(3)
@maxLength(3)
type instanceNumber = string

@export()
type resourceTags = {
  @description('所有者のメールアドレス')
  Owner: string

  @description('"{workloadCode}: {説明}" 形式。例: sre: Azure Observer for SRE')
  Project: string

  Environment: environment
}
