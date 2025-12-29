@Metadata.allowExtensions: true
@EndUserText.label: '##GENERATED Travel App (###)'
@Search.searchable: true
@ObjectModel: {
  sapObjectNodeType.name: 'ZRAP100_TRAV'
}
@AccessControl.authorizationCheck: #MANDATORY
@ObjectModel.semanticKey: ['TravelID'] //case-sensitive
define root view entity ZC_RAP100_TRAV
  provider contract transactional_query
  as projection on ZR_RAP100_TRAV
  association [1..1] to ZR_RAP100_TRAV as _BaseEntity on $projection.TravelID = _BaseEntity.TravelID
{

      @Search.defaultSearchElement: true
      @Search.fuzzinessThreshold: 0.90
  key TravelID,

      @Search.defaultSearchElement: true
      @ObjectModel.text.element: ['AgencyName'] //case-sensitive
      @Consumption.valueHelpDefinition: [{ entity : {name: '/DMO/I_Agency_StdVH', element: 'AgencyID' }, useForValidation: true }]
      AgencyID,
      _Agency.Name              as AgencyName,

      @Search.defaultSearchElement: true
      @ObjectModel.text.element: ['CustomerName'] //case-sensitive
      @Consumption.valueHelpDefinition: [{ entity : {name: '/DMO/I_Customer_StdVH', element: 'CustomerID' }, useForValidation: true }]
      CustomerID,
      _Customer.LastName        as CustomerName,

      BeginDate,
      EndDate,
      @Semantics: {
      amount.currencyCode: 'CurrencyCode'
      }
      BookingFee,
      @Semantics: {
      amount.currencyCode: 'CurrencyCode'
      }
      TotalPrice,

      @Consumption.valueHelpDefinition: [{ entity: {name: 'I_CurrencyStdVH', element: 'Currency' }, useForValidation: true }]
      CurrencyCode,
      Description,

      @ObjectModel.text.element: ['OverallStatusText'] //case-sensitive
      @Consumption.valueHelpDefinition: [{ entity: {name: '/DMO/I_Overall_Status_VH', element: 'OverallStatus' }, useForValidation: true }]
      OverallStatus,
      _OverallStatus._Text.Text as OverallStatusText : localized,

      Attachment,
      MimeType,
      FileName,
      LocalLastChangedAt,

      _BaseEntity
}
