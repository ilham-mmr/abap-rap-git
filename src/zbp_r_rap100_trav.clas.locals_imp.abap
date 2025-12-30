CLASS lhc_zr_rap100_trav DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    CONSTANTS: BEGIN OF travel_status,
                 open     TYPE c LENGTH 1 VALUE 'O', "Open
                 accepted TYPE c LENGTH 1 VALUE 'A', "Accepted
                 rejected TYPE c LENGTH 1 VALUE 'X', "Rejected
               END OF travel_status.
    METHODS:
      get_global_authorizations FOR GLOBAL AUTHORIZATION
        IMPORTING
        REQUEST requested_authorizations FOR ZrRap100Trav
        RESULT result,
      earlynumbering_create FOR NUMBERING
        IMPORTING entities FOR CREATE ZrRap100Trav,
      setStatusOpen FOR DETERMINE ON MODIFY
        IMPORTING keys FOR ZrRap100Trav~setStatusOpen,
      validateCustomer FOR VALIDATE ON SAVE
        IMPORTING keys FOR ZrRap100Trav~validateCustomer.

    METHODS validateDates FOR VALIDATE ON SAVE
      IMPORTING keys FOR ZrRap100Trav~validateDates.
    METHODS deductDiscount FOR MODIFY
      IMPORTING keys FOR ACTION ZrRap100Trav~deductDiscount RESULT result.
    METHODS copyTravel FOR MODIFY
      IMPORTING keys FOR ACTION ZrRap100Trav~copyTravel.
    METHODS acceptTravel FOR MODIFY
      IMPORTING keys FOR ACTION ZrRap100Trav~acceptTravel RESULT result.

    METHODS rejectTravel FOR MODIFY
      IMPORTING keys FOR ACTION ZrRap100Trav~rejectTravel RESULT result.
ENDCLASS.

CLASS lhc_zr_rap100_trav IMPLEMENTATION.
  METHOD get_global_authorizations.
  ENDMETHOD.
  METHOD earlynumbering_create.
    DATA:
      entity           TYPE STRUCTURE FOR CREATE zr_rap100_trav,
      travel_id_max    TYPE /dmo/travel_id,
      " change to abap_false if you get the ABAP Runtime error 'BEHAVIOR_ILLEGAL_STATEMENT'
      use_number_range TYPE abap_bool VALUE abap_false.

    "Ensure Travel ID is not set yet (idempotent)- must be checked when BO is draft-enabled
    LOOP AT entities INTO entity WHERE TravelID IS NOT INITIAL.
      APPEND CORRESPONDING #( entity ) TO mapped-zrrap100trav.
    ENDLOOP.

    DATA(entities_wo_travelid) = entities.
    "Remove the entries with an existing Travel ID
    DELETE entities_wo_travelid WHERE TravelID IS NOT INITIAL.
    IF use_number_range = abap_true.
      "Get numbers
      TRY.
          cl_numberrange_runtime=>number_get(
            EXPORTING
              nr_range_nr       = '01'
              object            = '/DMO/TRV_M'
              quantity          = CONV #( lines( entities_wo_travelid ) )
            IMPORTING
              number            = DATA(number_range_key)
              returncode        = DATA(number_range_return_code)
              returned_quantity = DATA(number_range_returned_quantity)
          ).
        CATCH cx_number_ranges INTO DATA(lx_number_ranges).
          LOOP AT entities_wo_travelid INTO entity.
            APPEND VALUE #(  %cid      = entity-%cid
                             %key      = entity-%key
                             %is_draft = entity-%is_draft
                             %msg      = lx_number_ranges
                          ) TO reported-zrrap100trav.
            APPEND VALUE #(  %cid      = entity-%cid
                             %key      = entity-%key
                             %is_draft = entity-%is_draft
                          ) TO failed-zrrap100trav.
          ENDLOOP.
          EXIT.
      ENDTRY.

      "determine the first free travel ID from the number range
      travel_id_max = number_range_key - number_range_returned_quantity.
    ELSE.
      "determine the first free travel ID without number range
      "Get max travel ID from active table
      SELECT SINGLE FROM zrap100_trav FIELDS MAX( travel_id ) AS travelID INTO @travel_id_max.
      "Get max travel ID from draft table
      SELECT SINGLE FROM zrap100_trav_d FIELDS MAX( travelid ) INTO @DATA(max_travelid_draft).
      IF max_travelid_draft > travel_id_max.
        travel_id_max = max_travelid_draft.
      ENDIF.
    ENDIF.
    "Set Travel ID for new instances w/o ID
    LOOP AT entities_wo_travelid INTO entity.
      travel_id_max += 1.
      entity-TravelID = travel_id_max.

      APPEND VALUE #( %cid      = entity-%cid
                      %key      = entity-%key
                      %is_draft = entity-%is_draft
                    ) TO mapped-zrrap100trav.
    ENDLOOP.

  ENDMETHOD.

  METHOD setStatusOpen.
    "Read travel instances of the transferred keys
    READ ENTITIES OF zr_rap100_trav IN LOCAL MODE
     ENTITY ZrRap100Trav
       FIELDS ( OverallStatus )
       WITH CORRESPONDING #( keys )
     RESULT DATA(travels)
     FAILED DATA(read_failed).

    "If overall travel status is already set, do nothing, i.e. remove such instances
    DELETE travels WHERE OverallStatus IS NOT INITIAL.
    CHECK travels IS NOT INITIAL.

    "else set overall travel status to open ('O')
    MODIFY ENTITIES OF zr_rap100_trav IN LOCAL MODE
      ENTITY ZrRap100Trav
        UPDATE SET FIELDS
        WITH VALUE #( FOR travel IN travels ( %tky    = travel-%tky
                                              OverallStatus = travel_status-open ) )
    REPORTED DATA(update_reported).

    "Set the changing parameter
    reported = CORRESPONDING #( DEEP update_reported ).

  ENDMETHOD.


**********************************************************************
* Validation: Check the validity of the entered customer data
**********************************************************************
  METHOD validateCustomer.
    "read relevant travel instance data
    READ ENTITIES OF zr_rap100_trav IN LOCAL MODE
    ENTITY ZrRap100Trav
     FIELDS ( CustomerID )
     WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

    DATA customers TYPE SORTED TABLE OF /dmo/customer WITH UNIQUE KEY customer_id.

    "optimization of DB select: extract distinct non-initial customer IDs
    customers = CORRESPONDING #( travels DISCARDING DUPLICATES MAPPING customer_id = customerID EXCEPT * ).
    DELETE customers WHERE customer_id IS INITIAL.
    IF customers IS NOT INITIAL.

      "check if customer ID exists
      SELECT FROM /dmo/customer FIELDS customer_id
                                FOR ALL ENTRIES IN @customers
                                WHERE customer_id = @customers-customer_id
        INTO TABLE @DATA(valid_customers).
    ENDIF.

    "raise msg for non existing and initial customer id
    LOOP AT travels INTO DATA(travel).

      APPEND VALUE #(  %tky                 = travel-%tky
                       %state_area          = 'VALIDATE_CUSTOMER'
                     ) TO reported-zrrap100trav.

      IF travel-CustomerID IS  INITIAL.
        APPEND VALUE #( %tky = travel-%tky ) TO failed-zrrap100trav.

        APPEND VALUE #( %tky                = travel-%tky
                        %state_area         = 'VALIDATE_CUSTOMER'
                        %msg                = NEW /dmo/cm_flight_messages(
                                                                textid   = /dmo/cm_flight_messages=>enter_customer_id
                                                                severity = if_abap_behv_message=>severity-error )
                        %element-CustomerID = if_abap_behv=>mk-on
                      ) TO reported-zrrap100trav.

      ELSEIF travel-CustomerID IS NOT INITIAL AND NOT line_exists( valid_customers[ customer_id = travel-CustomerID ] ).
        APPEND VALUE #(  %tky = travel-%tky ) TO failed-zrrap100trav.

        APPEND VALUE #(  %tky                = travel-%tky
                         %state_area         = 'VALIDATE_CUSTOMER'
                         %msg                = NEW /dmo/cm_flight_messages(
                                                                customer_id = travel-customerid
                                                                textid      = /dmo/cm_flight_messages=>customer_unkown
                                                                severity    = if_abap_behv_message=>severity-error )
                         %element-CustomerID = if_abap_behv=>mk-on
                      ) TO reported-zrrap100trav.
      ENDIF.

    ENDLOOP.


  ENDMETHOD.

**********************************************************************
* Validation: Check the validity of begin and end dates
**********************************************************************
  METHOD validateDates.

    READ ENTITIES OF zr_rap100_trav IN LOCAL MODE
      ENTITY ZrRap100Trav
        FIELDS (  BeginDate EndDate TravelID )
        WITH CORRESPONDING #( keys )
      RESULT DATA(travels).

    LOOP AT travels INTO DATA(travel).

      APPEND VALUE #(  %tky               = travel-%tky
                       %state_area        = 'VALIDATE_DATES' ) TO reported-zrrap100trav.

      IF travel-BeginDate IS INITIAL.
        APPEND VALUE #( %tky = travel-%tky ) TO failed-zrrap100trav.

        APPEND VALUE #( %tky               = travel-%tky
                        %state_area        = 'VALIDATE_DATES'
                         %msg              = NEW /dmo/cm_flight_messages(
                                                                textid   = /dmo/cm_flight_messages=>enter_begin_date
                                                                severity = if_abap_behv_message=>severity-error )
                      %element-BeginDate = if_abap_behv=>mk-on ) TO reported-zrrap100trav.
      ENDIF.
      IF travel-BeginDate < cl_abap_context_info=>get_system_date( ) AND travel-BeginDate IS NOT INITIAL.
        APPEND VALUE #( %tky               = travel-%tky ) TO failed-zrrap100trav.

        APPEND VALUE #( %tky               = travel-%tky
                        %state_area        = 'VALIDATE_DATES'
                         %msg              = NEW /dmo/cm_flight_messages(
                                                                begin_date = travel-BeginDate
                                                                textid     = /dmo/cm_flight_messages=>begin_date_on_or_bef_sysdate
                                                                severity   = if_abap_behv_message=>severity-error )
                        %element-BeginDate = if_abap_behv=>mk-on ) TO reported-zrrap100trav.
      ENDIF.
      IF travel-EndDate IS INITIAL.
        APPEND VALUE #( %tky = travel-%tky ) TO failed-zrrap100trav.

        APPEND VALUE #( %tky               = travel-%tky
                        %state_area        = 'VALIDATE_DATES'
                         %msg                = NEW /dmo/cm_flight_messages(
                                                                textid   = /dmo/cm_flight_messages=>enter_end_date
                                                               severity = if_abap_behv_message=>severity-error )
                        %element-EndDate   = if_abap_behv=>mk-on ) TO reported-zrrap100trav.
      ENDIF.
      IF travel-EndDate < travel-BeginDate AND travel-BeginDate IS NOT INITIAL
                                           AND travel-EndDate IS NOT INITIAL.
        APPEND VALUE #( %tky = travel-%tky ) TO failed-zrrap100trav.

        APPEND VALUE #( %tky               = travel-%tky
                        %state_area        = 'VALIDATE_DATES'
                        %msg               = NEW /dmo/cm_flight_messages(
                                                                textid     = /dmo/cm_flight_messages=>begin_date_bef_end_date
                                                                begin_date = travel-BeginDate
                                                                end_date   = travel-EndDate
                                                                severity   = if_abap_behv_message=>severity-error )
                        %element-BeginDate = if_abap_behv=>mk-on
                        %element-EndDate   = if_abap_behv=>mk-on ) TO reported-zrrap100trav.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.


**************************************************************************
* Instance-bound non-factory action with parameter `deductDiscount`:
* Deduct the specified discount from the booking fee (BookingFee)
**************************************************************************
  METHOD deductDiscount.
    DATA travels_for_update TYPE TABLE FOR UPDATE zr_rap100_trav.
    DATA(keys_with_valid_discount) = keys.

    " check and handle invalid discount values
    LOOP AT keys_with_valid_discount ASSIGNING FIELD-SYMBOL(<key_with_valid_discount>)
      WHERE %param-discount_percent IS INITIAL OR %param-discount_percent > 100 OR %param-discount_percent <= 0.

      " report invalid discount value appropriately
      APPEND VALUE #( %tky                       = <key_with_valid_discount>-%tky ) TO failed-zrrap100trav.

      APPEND VALUE #( %tky                       = <key_with_valid_discount>-%tky
                      %msg                       = NEW /dmo/cm_flight_messages(
                                                        textid = /dmo/cm_flight_messages=>discount_invalid
                                                        severity = if_abap_behv_message=>severity-error )
                      %element-TotalPrice        = if_abap_behv=>mk-on
                      %op-%action-deductDiscount = if_abap_behv=>mk-on
                    ) TO reported-zrrap100trav.

      " remove invalid discount value
      DELETE keys_with_valid_discount.
    ENDLOOP.

    " check and go ahead with valid discount values
    CHECK keys_with_valid_discount IS NOT INITIAL.

    " read relevant travel instance data (only booking fee)
    READ ENTITIES OF zr_rap100_trav IN LOCAL MODE
      ENTITY ZrRap100Trav
        FIELDS ( BookingFee )
        WITH CORRESPONDING #( keys_with_valid_discount )
      RESULT DATA(travels).

    LOOP AT travels ASSIGNING FIELD-SYMBOL(<travel>).
      DATA percentage TYPE decfloat16.
      DATA(discount_percent) = keys_with_valid_discount[ KEY draft %tky = <travel>-%tky ]-%param-discount_percent.
      percentage =  discount_percent / 100 .
      DATA(reduced_fee) = <travel>-BookingFee * ( 1 - percentage ) .

      APPEND VALUE #( %tky       = <travel>-%tky
                      BookingFee = reduced_fee
                    ) TO travels_for_update.
    ENDLOOP.

    " update data with reduced fee
    MODIFY ENTITIES OF zr_rap100_trav IN LOCAL MODE
      ENTITY ZrRap100Trav
        UPDATE FIELDS ( BookingFee )
        WITH travels_for_update.

    " read changed data for action result
    READ ENTITIES OF zr_rap100_trav IN LOCAL MODE
      ENTITY ZrRap100Trav
        ALL FIELDS WITH
        CORRESPONDING #( travels )
      RESULT DATA(travels_with_discount).

    " set action result
    result = VALUE #( FOR travel IN travels_with_discount ( %tky   = travel-%tky
                                                            %param = travel ) ).
  ENDMETHOD.



**************************************************************************
* Instance-bound factory action `copyTravel`:
* Copy an existing travel instance
**************************************************************************
  METHOD copyTravel.
    DATA:
       travels       TYPE TABLE FOR CREATE zr_rap100_trav.

    " remove travel instances with initial %cid (i.e., not set by caller API)
    READ TABLE keys WITH KEY %cid = '' INTO DATA(key_with_inital_cid).
    ASSERT key_with_inital_cid IS INITIAL.

    " read the data from the travel instances to be copied
    READ ENTITIES OF zr_rap100_trav IN LOCAL MODE
       ENTITY ZrRap100Trav
       ALL FIELDS WITH CORRESPONDING #( keys )
    RESULT DATA(travel_read_result)
    FAILED failed.

    LOOP AT travel_read_result ASSIGNING FIELD-SYMBOL(<travel>).
      " fill in travel container for creating new travel instance
      APPEND VALUE #( %cid      = keys[ KEY entity %key = <travel>-%key ]-%cid
                     %is_draft = keys[ KEY entity %key = <travel>-%key ]-%param-%is_draft
                     %data     = CORRESPONDING #( <travel> EXCEPT TravelID )
                  )
      TO travels ASSIGNING FIELD-SYMBOL(<new_travel>).

      " adjust the copied travel instance data
      "" BeginDate must be on or after system date
      <new_travel>-BeginDate     = cl_abap_context_info=>get_system_date( ).
      "" EndDate must be after BeginDate
      <new_travel>-EndDate       = cl_abap_context_info=>get_system_date( ) + 30.
      "" OverallStatus of new instances must be set to open ('O')
      <new_travel>-OverallStatus = travel_status-open.
    ENDLOOP.

    " create new BO instance
    MODIFY ENTITIES OF  zr_rap100_trav IN LOCAL MODE
       ENTITY ZrRap100Trav
       CREATE FIELDS ( AgencyID CustomerID BeginDate EndDate BookingFee
                         TotalPrice CurrencyCode OverallStatus Description )
          WITH travels
       MAPPED DATA(mapped_create).

    " set the new BO instances
    mapped-zrrap100trav   =  mapped_create-zrrap100trav .
  ENDMETHOD.

*************************************************************************************
* Instance-bound non-factory action: Set the overall travel status to 'A' (accepted)
*************************************************************************************
  METHOD acceptTravel.
    " modify travel instance
    MODIFY ENTITIES OF zr_rap100_trav IN LOCAL MODE
       ENTITY ZrRap100Trav
       UPDATE FIELDS ( OverallStatus )
       WITH VALUE #( FOR key IN keys ( %tky          = key-%tky
                                        OverallStatus = travel_status-accepted ) )  " 'A'
    FAILED failed
    REPORTED reported.

    " read changed data for action result
    READ ENTITIES OF zr_rap100_trav IN LOCAL MODE
       ENTITY ZrRap100Trav
       ALL FIELDS WITH
       CORRESPONDING #( keys )
       RESULT DATA(travels).

    " set the action result parameter
    result = VALUE #( FOR travel IN travels ( %tky   = travel-%tky
                                             %param = travel ) ).
  ENDMETHOD.

*************************************************************************************
* Instance-bound non-factory action: Set the overall travel status to 'X' (rejected)
*************************************************************************************
  METHOD rejectTravel.
   " modify travel instance
    MODIFY ENTITIES OF zr_rap100_trav IN LOCAL MODE
       ENTITY ZrRap100Trav
       UPDATE FIELDS ( OverallStatus )
       WITH VALUE #( FOR key IN keys ( %tky          = key-%tky
                                        OverallStatus = travel_status-rejected ) )  " 'X'
    FAILED failed
    REPORTED reported.

    " read changed data for action result
    READ ENTITIES OF zr_rap100_trav IN LOCAL MODE
       ENTITY ZrRap100Trav
       ALL FIELDS WITH
       CORRESPONDING #( keys )
       RESULT DATA(travels).

    " set the action result parameter
    result = VALUE #( FOR travel IN travels ( %tky   = travel-%tky
                                             %param = travel ) ).
  ENDMETHOD.

ENDCLASS.
