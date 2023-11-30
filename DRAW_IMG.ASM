	.model small
	.stack 100h
	.data
	pspSeg dw ?
	fileDesc dw ?
	fileStreamBuffer db 0,0,0,0,0,0,0,0
	magicString db 'magica'
	
	imageType db ?
	imageWidth dw ?
	imageHeight dw ?
	
	textModeRowOffset dw ?		; Адрес конечного знака в строке
	textModeMaxRowOffset dw ?	; Адрес конечного знака в изображении
	
	gdcModeCurRowOffset dw ? 	; Смещение начала ТЕКУЩЕЙ строки
	gdcModeEndRowOffset dw ?	; Смещение конца изображения (конечной строки)
	.code
	;
	;
	; --TODO--
	; ДОРАБОТАТЬ ОПРЕДЕЛЕНИЕ РАЗМЕРОВ ИЗОБРАЖЕНИЯ И ПОЗВОЛИТЬ РИСОВАТЬ КАРТИНКИ БОЛЬШЕ ЭКРАНА
	; ДОРАБОТАТЬ ОПРЕДЕЛЕНИЕ ГРАНИЦ ЭКРАНА
	;
	;
	mov ax,@data
	mov ds,ax
	mov pspSeg,es
	
	;====================================
	; Превращаем аргумент в строку ASCIIZ
	;====================================
	mov ah,00h
	mov al,byte ptr es:[80h] ; Длина аргумента
	mov si,ax
	cmp si,00h
	jne chngArgNoError
	jmp fileOpenError
	chngArgNoError:
	
	add si,81h ; Адрес символа возврата каретки
	mov es:[si],byte ptr 00h ; Меняем его на терминатор
	;------------------------------------
	
	;=====================
	; Открываем дескриптор (файл)
	;=====================
	push ds
	mov ax,pspSeg
	mov ds,ax
	mov dx,82h
	mov ax,3d00h
	int 21h
		jnc noOpenError
		jmp fileOpenError
		noOpenError:
	pop ds
	mov bx,ax ; Перемещаем дескриптор в BX
	mov fileDesc,ax ; И в память
	;---------------------
	; (Дескриптор находится в BX)
	
	;===================
	; Читаем изображение
	;===================
	; Читаем магическое слово
	mov dx,offset fileStreamBuffer ; DS:DX - буфер чтения
	mov cx,06h ; Количество байт
	mov ah,3fh ; Читать файл
	int 21h
	jnc imgReadFileContinue ; Если файл кончился, надо закрыть
		jmp fileEndMark
	imgReadFileContinue:
	
	; Сверяем магическое слово
	mov si,offset fileStreamBuffer
	mov di,offset magicString
	mov cx,06h
	checkMagicLoop:
		mov ah,byte ptr ds:[si] ; Берём прочитанный символ
		mov al,byte ptr ds:[di] ; Берём ожидаемый символ
		cmp ah,al ; Сравниваем их
			je magicCharacterOk
			jmp fileEndMark
			magicCharacterOk:
		inc si
		inc di
	loop checkMagicLoop
	
	; Получаем тип изображения
	mov dx,offset imageType ; DS:DX - буфер чтения
	mov cx,01h ; Количество байт
	mov ah,3fh ; Читать файл
	int 21h
	jnc imgTypeContinue ; Если файл кончился, надо закрыть
		jmp fileEndMark
	imgTypeContinue:
	
	; Получаем размеры изображения
	mov dx,offset imageWidth ; DS:DX - буфер чтения
	mov cx,02h ; Количество байт
	mov ah,3fh ; Читать файл
	int 21h
	mov ah,3fh ; Читать файл
	mov dx,offset imageHeight ; DS:DX - буфер чтения
	int 21h
	jnc imgSizeContinue ; Если файл кончился, надо закрыть
		jmp fileEndMark
	imgSizeContinue:
	
	; Проверяем тип
	; Пока что программа умеет только в type:2 (текстовый режим)
	mov ah,imageType
	cmp ah,01h
	je drawGDCImageBranch
	cmp ah,02h
	je drawTextImageBranch
	jmp fileEndMark ; Неизвестный тип изображения, закрываем
	
	;===============================
	; Ветка для графических картинок
	;===============================
	drawGDCImageBranch:
	; Инициализируем GDC (говорим ему работать на CRT) (Аналог INT 18H AH=40H)
	mov al,0dh
	out 0a2h,al
	
	; Включаем графический режим 640x400 (тип 1)
	mov al,02h
	out 68h,al ; カラーグラフィックモード
	mov al,08h
	out 68h,al ; 高解像度
;	mov al,41h ; Плазменный дисплей
	mov al,40h ; ЭЛТ экран
	out 6ah,al ; プラズマディスプレィ
	mov al,01h
	out 6ah,al ; 16 COLOR MODE
	; ОТ СЕБЯ: GDC 5MHz
	mov al,83h
	out 6ah,al
	mov al,85h
	out 6ah,al
	; GDC 2.5MHz
;	mov al,84h
;	out 6ah,al

	mov al,4bh
	out 0a2h,al ; ライン数設定コマンド
	mov al,00h
	out 0a0h,al ; 縦倍率 等倍

	; Переключение 2-х буферов вывода (орёл/решка)
	out 0a4h,al ; 表ページ表示
	out 0a6h,al ; 表ページ描画
	; Рисуем картинку (тип 1)
	call drawGDCCompressedImage
	jmp fileEndMark
	;-------------------------------
	;=============================
	; Ветка для текстовых картинок
	;=============================
	drawTextImageBranch:
	; Рисуем картинку (тип 2)
	call drawTextModeImage
	jmp fileEndMark
	;-----------------------------
	;-------------------
	
	fileEndMark:
	; Закрываем файл
	mov ah,3eh ; Закрыть файл
	mov bx,fileDesc ; Дескриптор файла
	int 21h
	
	; Выходим из программы
	mov ax,4c00h
	int 21h
	ret
	
	; Выход при ошибке открытия
	fileOpenError:
	mov ax,4c0fh
	int 21h
	ret
	
clearScreen proc near
	push ax
	push es
	push si
	push di
	push cx
	
	mov ax,0a000h
	mov es,ax
	mov si,0
	mov di,2000h
	mov cx,2000
	
	clearScreenLoop:
		mov es:[si],word ptr 00h
		mov es:[di],byte ptr 0e1h ; Меняем цвет текста на белый
		add si,2
		add di,2
	loop clearScreenLoop
	
	pop cx
	pop di
	pop si
	pop es
	pop ax
	ret
clearScreen endp
drawGDCImage proc near
	;===================
	; Определяем палитру (вот это я, конечно, намудрил ради всего-то 16 цветов...)
	;===================
	mov bl,00h ; Номер цвета в палитре
	mov cx,08h ; Общее число ПАР цветов
	definePaletteLoop:
		push bx
		push cx
		; Читаем 2 цвета сразу
		mov dx,offset fileStreamBuffer ; DS:DX - буфер чтения
		mov cx,03h ; Количество байт (rg|br|gb)
		mov ah,3fh ; Читать файл
		mov bx,fileDesc
		int 21h
		pop cx
		pop bx
		
		push cx
		; Записываем цвет в палитру
		mov si,dx
			; Читаем первый байт
			mov ah,byte ptr ds:[si] ;bh=rrrrgggg
			mov al,ah ;bx=rrrrggggrrrrgggg
			and ah,0f0h ;bh=rrrr0000
			and al,00fh ;bl=0000gggg
			mov cl,4
			shr ah,cl ;bh=0000rrrr
		
			; Записываем красный и зелёный компоненты
			push ax
			mov al,bl
			out 0a8h,al
			pop ax
			out 0aah,al ; GREEN
			mov al,ah
			out 0ach,al ; RED
		
			; Читаем второй байт
			inc si
			mov ah,byte ptr ds:[si] ;bh=bbbbrrrr
			mov al,ah ;bx=bbbbrrrrbbbbrrrr
			and ah,0f0h ;bh=bbbb0000
			and al,00fh ;bl=0000rrrr
			mov cl,4
			shr ah,cl ;bh=0000bbbb
		
			; Записываем синий и красный компоненты (красный уже от второго цвета)
			push ax
			mov al,ah
			out 0aeh,al ; BLUE
			pop ax
			inc bl ; Переходим к следующему цвету
			push ax
			mov al,bl
			out 0a8h,al
			pop ax
			out 0ach,al ; RED
		
			; Читаем третий байт
			inc si
			mov ah,byte ptr ds:[si] ;bh=ggggbbbb
			mov al,ah ;bx=ggggbbbbggggbbbb
			and ah,0f0h ;bh=gggg0000
			and al,00fh ;bl=0000bbbb
			mov cl,4
			shr	ah,cl ;bh=0000gggg
		
			; Записываем зелёный и синий компоненты второго цвета
			out 0aeh,al ; BLUE
			mov al,ah
			out 0aah,al ; GREEN
			inc bl ; Переходим к следующему цвету
		pop cx
	loop definePaletteLoop
	;-------------------
	
	;================================
	; Выводим битмап на экран (тип 1)
	;================================
	mov si,00h
	mov dh,00h
	readGDCBitmapNextByte:
push dx
		mov dx,offset fileStreamBuffer ; DS:DX - буфер чтения
		mov cx,01h ; Количество байт
		mov ah,3fh ; Читать файл
		mov bx,fileDesc
		int 21h
pop dx
		jc endReadingGDC
		cmp ax,00
		jne drawGDCFileContinue
			endReadingGDC:
			jmp drawGDCModeEnd
		drawGDCFileContinue:
		
		mov ah,byte ptr ds:[offset fileStreamBuffer] ; Получаем прочитанный байт
		; Получаем цвет последовательности
		mov dl,ah
		and dl,00fh
		; Получаем длину последовательности
		and ah,0f0h
		mov cl,4
		shr ah,cl
		mov ch,0
		mov cl,ah
		
		; Рисуем цвет DL CL раз (CL <= 8)
		cmp cl,00
		je readGDCBitmapNextByte
		
		; ПРОВЕРКА НА CL < 8
		drawGDCImageRunLength:
		push cx
		cmp cl,08
		jna skipCuttingRunLength1
			mov cl,08
		skipCuttingRunLength1:
		; Повторяем 4 раза для каждой плоскости
			push cx
			
			; Создаём маску для записи
			mov bx,0ffffh
			shr bx,cl
			mov cl,dh
			ror bx,cl
			
			mov ax,0a800h
			mov es,ax
			push dx
			and dl,01h
			call drawRLEOnPlane
			pop dx
			
			mov ax,0b000h
			mov es,ax
			push dx
			and dl,02h
			call drawRLEOnPlane
			pop dx
			
			mov ax,0b800h
			mov es,ax
			push dx
			and dl,04h
			call drawRLEOnPlane
			pop dx
			
			mov ax,0e000h
			mov es,ax
			push dx
			and dl,08h
			call drawRLEOnPlane
			pop dx
			
			pop cx
		; Перемещаем указатели (когда заполним все плоскости)
		add dh,cl
		cmp dh,08h
		jb skipMovingBytePointer
			inc si
			sub dh,08h
		skipMovingBytePointer:
		pop cx
		;; Добавить проверку по ширине самого изображения
		;; Проверяем на выход за пределы экрана
		; Проверка выхода за пределы плоскости
		cmp si,7d00h
		jae drawGDCModeEnd
		
		; Если ещё осталось что выводить (в cl), то повторяем операцию
		cmp cl,08
		jna skipCuttingRunLength2
			sub cl,08
			jmp drawGDCImageRunLength
		skipCuttingRunLength2:
	jmp readGDCBitmapNextByte
	;--------------------------------
	
	drawGDCModeEnd:
	ret
drawGDCImage endp
drawGDCCompressedImage proc near
	;===================
	; Определяем палитру (вот это я, конечно, намудрил ради всего-то 16 цветов...)
	;===================
	mov bl,00h ; Номер цвета в палитре
	mov cx,08h ; Общее число ПАР цветов
	definePaletteLoop1:
		push bx
		push cx
		; Читаем 2 цвета сразу
		mov dx,offset fileStreamBuffer ; DS:DX - буфер чтения
		mov cx,03h ; Количество байт (rg|br|gb)
		mov ah,3fh ; Читать файл
		mov bx,fileDesc
		int 21h
		pop cx
		pop bx
		
		push cx
		; Записываем цвет в палитру
		mov si,dx
			; Читаем первый байт
			mov ah,byte ptr ds:[si] ;bh=rrrrgggg
			mov al,ah ;bx=rrrrggggrrrrgggg
			and ah,0f0h ;bh=rrrr0000
			and al,00fh ;bl=0000gggg
			mov cl,4
			shr ah,cl ;bh=0000rrrr
		
			; Записываем красный и зелёный компоненты
			push ax
			mov al,bl
			out 0a8h,al
			pop ax
			out 0aah,al ; GREEN
			mov al,ah
			out 0ach,al ; RED
		
			; Читаем второй байт
			inc si
			mov ah,byte ptr ds:[si] ;bh=bbbbrrrr
			mov al,ah ;bx=bbbbrrrrbbbbrrrr
			and ah,0f0h ;bh=bbbb0000
			and al,00fh ;bl=0000rrrr
			mov cl,4
			shr ah,cl ;bh=0000bbbb
		
			; Записываем синий и красный компоненты (красный уже от второго цвета)
			push ax
			mov al,ah
			out 0aeh,al ; BLUE
			pop ax
			inc bl ; Переходим к следующему цвету
			push ax
			mov al,bl
			out 0a8h,al
			pop ax
			out 0ach,al ; RED
		
			; Читаем третий байт
			inc si
			mov ah,byte ptr ds:[si] ;bh=ggggbbbb
			mov al,ah ;bx=ggggbbbbggggbbbb
			and ah,0f0h ;bh=gggg0000
			and al,00fh ;bl=0000bbbb
			mov cl,4
			shr	ah,cl ;bh=0000gggg
		
			; Записываем зелёный и синий компоненты второго цвета
			out 0aeh,al ; BLUE
			mov al,ah
			out 0aah,al ; GREEN
			inc bl ; Переходим к следующему цвету
		pop cx
	loop definePaletteLoop1
	;-------------------
	; Тут рисуем...
	mov ax,0a800h
	mov es,ax
	call drawGDCCompressedFillPlane
	mov ax,0b000h
	mov es,ax
	call drawGDCCompressedFillPlane
	mov ax,0b800h
	mov es,ax
	call drawGDCCompressedFillPlane
	mov ax,0e000h
	mov es,ax
	call drawGDCCompressedFillPlane
	
	ret
drawGDCCompressedImage endp
drawGDCCompressedFillPlane proc near
	; Единственная задача этой процедуры - заполнять выбранную плоскость данными из файла
	;================================
	; Выводим битмап на экран (тип 1)
	;================================
	; si - Указатель байта пикселя для записи
	; di - Конечный адрес для текущей строки
	; dh - Указатель бита пикселя для записи
	; dl - Бит для записи
	; cl - Кол-во бит для записи
	; es - Сегмент плоскости для записи
	; Вычисляем конечный адрес для строки
	mov dx,0
	mov ax,imageWidth
	mov bx,8
	div bx ; Делим ширину изображения на 8
	cmp dx,00 ; Округляем в большую сторону
	je skipIncRowOffset
		inc ax
	skipIncRowOffset:
	mov di,ax
	mov gdcModeCurRowOffset,00h
	
	; Вычисляем конечный адрес картинки (после последней строки)
	mov ax,imageHeight
	mov bx,80
	mul bx
	mov gdcModeEndRowOffset,ax
	
	; Обнуляем указатели
	mov si,00h
	mov dx,00h
	
	; Читаем байт из файла
drawCompressedNextByte:
	push dx
	mov dx,offset fileStreamBuffer ; DS:DX - буфер чтения
	mov cx,01h ; Количество байт (rg|br|gb)
	mov ah,3fh ; Читать файл
	mov bx,fileDesc
	int 21h
	pop dx
	jc endReadGDC
	cmp ax,00
	jne drawGDCContinue
		endReadGDC:
		jmp drawCompressedEnd
	drawGDCContinue:
	mov al,fileStreamBuffer ; Помещаем прочитанный байт в AL
	
	; Декодируем полученный байт
	cmp al,128
	jnb drawGDCRun
		jmp drawGDCOctet ; Если r=0 (по сути, AL<10000000b), декодируем октет
	drawGDCRun: ; Если r=1, декодируем серию
		; Декодируем серию бит
		; Помещаем длину серии в CX
		mov ch,0
		mov cl,al
		and cl,3fh
		
		; Помещаем бит для записи в DL
		mov dl,al
		and dl,40h
		
		; Рисуем серию бит
		; Оптимизировать вот эту часть кода
		continueDrawBitRun:
		push cx
			; Пробуем рисовать только по 8 бит за раз
			cmp cl,8
			jna drawGDCskipRunLengthCut
				mov cl,8
			drawGDCskipRunLengthCut:
		
			; Создаём маску для записи
			push cx
			mov bx,0ffffh
			shr bx,cl
			mov cl,dh
			ror bx,cl
			pop cx
			
			; Сохраняем адрес первого байта
			push si
			; ДО ЭТОГО ВТОРОЙ БАЙТ ВСЕГДА БЫЛ ВТОРЫМ БАЙТОМ... НЕ СТОИТ ПРЕНЕБРЕГАТЬ ЭТИМ
			inc si
;			; Двигаем указатель бита
;			; Вот этот блок кода передвинуть на своё привычное место (после применения маски)
;			add dh,cl
;			cmp dh,8
;			jb drawGDCskipMovingBytePointer0
;				inc si
;				sub dh,8
;			drawGDCskipMovingBytePointer0:
			; И после этого блока кода тоже проверять на конец строки... На всякий случай, если не заработает
			; Проверка на конец строки
			cmp si,di
			jnae maskLowPointerCheckEnd0
				add di,80 ; Переходим на новую строку
				add gdcModeCurRowOffset,80 ; Переходим на новую строку
				mov si,gdcModeCurRowOffset
				
				; Проверяем на конец картинки
				; В случае конца картинки нарисовать только первый байт
;				cmp si,gdcModeEndRowOffset
;				jnae imageNotEnd0
;					; Рисуем только первый байт
;					pop si
;					; ...
;					
;					pop cx ; Очищаем стек от излишков
;					ret
;				imageNotEnd0:
			maskLowPointerCheckEnd0:
			; Сохраняем адрес второго байта (он уже в SI)
			;push si
			
			; Применяем маску
			cmp dl,00
			jne drawGDCbitMaskHigh
				and byte ptr es:[si],bl ; Маска ко второму байту
				pop si
				and byte ptr es:[si],bh ; Маска к первому байту
				
				jmp drawGDCuseMaskEnd
			drawGDCbitMaskHigh:
				not bx
				
				or byte ptr es:[si],bl ; Маска ко второму байту
				pop si
				or byte ptr es:[si],bh ; Маска к первому байту
			drawGDCuseMaskEnd:
		
			; Двигаем указатели
			add dh,cl
			cmp dh,8
			jb drawGDCskipMovingBytePointer1
				inc si
				sub dh,8
				
				; Проверяем на конец картинки
				; Попробовать проверять ТОЛЬКО на конец картинки... Хоть и звучит бредово
				cmp si,gdcModeEndRowOffset
				jnae imageNotEnd1
					pop cx ; Очищаем стек от излишков
					ret
				imageNotEnd1:
				
				; Проверка на конец строки
				;(Этот кусок кода ни к чему не привёл)
;				cmp si,di
;				jnae maskLowPointerCheckEnd1
;					add di,80 ; Переходим на новую строку
;					add gdcModeCurRowOffset,80 ; Переходим на новую строку
;					mov si,gdcModeCurRowOffset
;				
;					; Проверяем на конец картинки
;					cmp si,gdcModeEndRowOffset
;					jnae imageNotEnd1
;						pop cx ; Очищаем стек от излишков
;						ret
;					imageNotEnd1:
;				maskLowPointerCheckEnd1:
			drawGDCskipMovingBytePointer1:
		pop cx
		; Проверяем, остались ли ещё биты для записи
		; Если ещё осталось что выводить (в cl), то повторяем операцию
		cmp cl,8
		jna skipCutRunLength
			sub cl,8
			jmp continueDrawBitRun
		skipCutRunLength:
		
		jmp drawGDCDecodingEnd
	drawGDCOctet:
		; Декодируем октет
		; Октет для записи уже лежит в AL.. Надо только следка подвинуть его в самое начало AH
		mov ah,al
		shl ah,1
		mov al,0
		
		; Создаём обнуляющую маску
		mov bx,1ffh ; 7 нулей и 1-чки
		mov cl,dh
		ror bx,cl
		shr ax,cl
		
		; В AX - серия для записи
		; В BX - маска для записи
		; Применяем маску
		;
		; Проблема наверняка в реализации проверки в этой ветке (Пиксели чередуются 6 раз и повторяются... CHECK1-2.PIC) (Что за чёрт?!) (Сделать ещё радужную картинку для проверки)
		;
		and byte ptr es:[si],bh
		or byte ptr es:[si],ah
		push si
		inc si
		; Двигаем указатели...
		cmp si,di
		jnae maskLowPointerCheckEnd3
			add di,80 ; Переходим на новую строку
			add gdcModeCurRowOffset,80 ; Переходим на новую строку
			mov si,gdcModeCurRowOffset
			
			; Проверяем на конец картинки
			cmp si,gdcModeEndRowOffset
			jnae imageNotEnd3
				pop si ; Очищаем стек от излишков
				ret
			imageNotEnd3:
		maskLowPointerCheckEnd3:
		and byte ptr es:[si],bl
		or byte ptr es:[si],al
		pop si ; ПОСМОТРЕТЬ, КАК ЭТО РАБОТАЕТ ПОСЛЕ ПРОВЕРКИ КОНЦА СТРОКИ
		
		; Двигаем указатели
		add dh,7
		cmp dh,8
		jb drawGDCskipMovingBytePointer3
			inc si
			sub dh,8
		drawGDCskipMovingBytePointer3:
	drawGDCDecodingEnd:
	
	; Попробовать и сюда, на всякий, случай запихнуть проверку конца строки
	
	; Читаем ещё один байт
jmp drawCompressedNextByte
	;--------------------------------
	drawCompressedEnd:
	ret
drawGDCCompressedFillPlane endp
drawRLEOnPlane proc near
	; Вводные данные:
	; ES - сегментный адрес плоскости
	; SI - смещение байта в плоскости
	; DL - бит для записи
	; BX - маска для записи в байт
	
	; Применяем маску
;	cmp dl,00
;	jne drawGDCbitMaskHigh
;		and byte ptr es:[si],bh
;		inc si
;		and byte ptr es:[si],bl
;		jmp drawGDCuseMaskEnd
;	drawGDCbitMaskHigh:
;		not bx
;		or byte ptr es:[si],bh
;		inc si
;		or byte ptr es:[si],bl
;		not bx
;	drawGDCuseMaskEnd:
;	dec si
	
	ret
drawRLEOnPlane endp
drawTextModeImage proc near
	;=========================================================
	; Находим предельные адреса знакомест для картинки (тип 2)
	;=========================================================
	; textModeRowOffset
	mov ax,imageWidth
	mov bx,2
	mul bx
	;; ; При необходимости добавляем смещение левого верхнего угла
	; Обрезаем лишнее
	cmp ax,160
	jbe textModeRowOffsetCutEnd
		mov ax,160
	textModeRowOffsetCutEnd:
	mov textModeRowOffset,ax
	
	; textModeMaxRowOffset
	mov ax,imageHeight
	dec ax
	mov bx,160
	mul bx
	;; ; При необходимости добавляем смещение левого верхнего угла
	; Обрезаем лишнее
	add ax,textModeRowOffset
	cmp ax,4000
	jbe textModeMaxRowOffsetCutEnd
		mov ax,4000
	textModeMaxRowOffsetCutEnd:
	mov textModeMaxRowOffset,ax
	;---------------------------------------------------------
	;================================
	; Выводим битмап на экран (тип 2)
	;================================
	call clearScreen ; Сначала убираем буквы на экране
	; SI - адрес знакоместа
	; DI - адрес всей строки
	mov ax,0a200h ; Сегмент текстовой видеопамяти (слой с атрибутами знакоместа)
	mov es,ax
	mov si,00h
	mov di,00h
	readBitmapNextByte:
		mov dx,offset fileStreamBuffer ; DS:DX - буфер чтения
		mov cx,01h ; Количество байт
		mov ah,3fh ; Читать файл
		mov bx,fileDesc
		int 21h
		jc drawTextModeEnd
		cmp ax,00
		je drawTextModeEnd
		
		mov ah,byte ptr ds:[offset fileStreamBuffer] ; Получаем прочитанный байт
		; Получаем цвет последовательности
		mov dl,ah
		and dl,00fh
		;; ; Преобразуем цвет для лёгкой записи в память
		; Если цвет чёрный, сделать белый цвет символов (и чёрный фон)
		cmp dl,0
		je textConversionBlack
			mov cl,5
			shl dl,cl ; Переносим цвет влево
			or dl,05h ; Атрибуты знакоместа: RV, ST
			jmp endTextColorConvertion
		textConversionBlack:
			mov dl,0e1h
		endTextColorConvertion:
		; Получаем длину последовательности
		and ah,0f0h
		mov cl,4
		shr ah,cl
		mov ch,0
		mov cl,ah
		
		; Рисуем цвет DL CL раз
		cmp cx,00
		je readBitmapNextByte ; Защита от переполнения
		drawPixelLoop:
			mov es:[si],dl ; Пишем фон символа в память
			add si,2 ; Следующий символ
			
			; Проверяем на выход за пределы экрана
			cmp si,textModeRowOffset
			jb textModeDrawRowChecked
				; Переходим на следующую строку
				add di,160
				add textModeRowOffset,160
				mov si,di
				; Если вышли за нижнюю границу, то закрываем файл
				cmp si,textModeMaxRowOffset
				ja drawTextModeEnd
			textModeDrawRowChecked:
		loop drawPixelLoop
	jmp readBitmapNextByte
	;--------------------------------
	
	drawTextModeEnd:
	ret
drawTextModeImage endp
	end